# A saved agile board.
#
# Subclasses IssueQuery rather than Query: every issue filter, every column,
# `statement`, `project_statement` and the whole visibility model then come from
# core unchanged. RedmineUP subclasses Query and re-implements all of it, which
# is most of why their query model is 26 KB.
#
# The board's own settings ride in the serialized `options` column, so a saved
# board is one row in Redmine's `queries` table with no extra schema.
class ExpertAgileQuery < IssueQuery
  include RedmineExpertAgile::BoardGrid

  # Reading a board only needs the agile permission; the inherited
  # :view_issues check still applies to the issues themselves via Issue.visible.
  self.view_permission = :view_expert_agile_board

  # STI guard for our own listings. IssueQuery.visible would otherwise return
  # agile boards too — see QueriesHelperPatch, which keeps them out of the
  # issue list sidebar.
  scope :only_boards, -> { where(:type => name) }

  BOARD_TYPES = %w(kanban scrum).freeze

  # Card fields we render ourselves and therefore never repeat in the generic
  # attribute list at the bottom of a card.
  SPECIAL_CARD_COLUMNS = %i(id project tracker status subject assigned_to done_ratio
                            estimated_hours spent_hours story_points).freeze

  def initialize(attributes = nil, *args)
    super
    self.filters ||= { 'status_id' => { :operator => 'o', :values => [''] } }
  end

  # --- Options -------------------------------------------------------
  #
  # Thin typed accessors over the serialized hash, so callers never poke at
  # `options[...]` directly and the stored shape stays in one place.

  def board_type
    value = options[:board_type].to_s
    BOARD_TYPES.include?(value) ? value : 'kanban'
  end

  def board_type=(value)
    options[:board_type] = BOARD_TYPES.include?(value.to_s) ? value.to_s : 'kanban'
  end

  # Ids of the statuses shown as columns. Empty means "every open status".
  def board_status_ids
    Array(options[:board_status_ids]).map(&:to_i).reject(&:zero?)
  end

  def board_status_ids=(ids)
    options[:board_status_ids] = Array(ids).map(&:to_i).reject(&:zero?)
  end

  # {status_id => [min, max]}, either bound optional.
  #
  # Stored as a real hash of integer pairs, not RedmineUP's "2-7" string that
  # has to be re-parsed with a regex on every render.
  def wip_limits
    (options[:wip_limits] || {}).each_with_object({}) do |(status_id, bounds), acc|
      min, max = Array(bounds)
      acc[status_id.to_i] = [min.presence && min.to_i, max.presence && max.to_i]
    end
  end

  def wip_limits=(limits)
    normalized = (limits || {}).each_with_object({}) do |(status_id, bounds), acc|
      min, max = Array(bounds)
      min = min.presence && min.to_i
      max = max.presence && max.to_i
      acc[status_id.to_i] = [min, max] if min || max
    end
    options[:wip_limits] = normalized
  end

  def color_base
    value = options[:color_base].to_s
    RedmineExpertAgile::COLOR_BASES.include?(value) ? value : RedmineExpertAgile.color_base
  end

  def color_base=(value)
    options[:color_base] = value.to_s
  end

  # Swimlanes reuse Redmine's grouping, so this is just `group_by` under a name
  # that matches what the UI calls it.
  def swimlane_field
    group_by
  end

  def swimlane_field=(value)
    self.group_by = value
  end

  def card_columns
    names = Array(options[:card_column_names]).map(&:to_sym)
    names = RedmineExpertAgile.default_card_columns if names.empty?
    available_columns.select { |column| names.include?(column.name) }
  end

  def card_column_names=(names)
    options[:card_column_names] = Array(names).reject(&:blank?).map(&:to_sym)
  end

  # Extra card fields, i.e. everything not already drawn as a dedicated part of
  # the card.
  def extra_card_columns
    card_columns.reject { |column| SPECIAL_CARD_COLUMNS.include?(column.name) }
  end

  def sprint_id
    options[:sprint_id].presence && options[:sprint_id].to_i
  end

  def sprint_id=(value)
    options[:sprint_id] = value.presence && value.to_i
  end

  def backlog_enabled?
    options[:backlog_enabled].to_s == '1'
  end

  def backlog_enabled=(value)
    options[:backlog_enabled] = value.to_s == '1' ? '1' : '0'
  end

  # --- Visibility ----------------------------------------------------

  def editable_by?(user)
    return false unless user
    return true if user.admin?
    return user.allowed_to?(:add_expert_agile_queries, project) if is_private?

    user.allowed_to?(:manage_public_expert_agile_queries, project)
  end

  # --- Columns -------------------------------------------------------

  # Swimlanes are built by loading the grouped association's records, which
  # only works for association-backed columns — a custom field column has no
  # `reflect_on_association`. Excluding them here is what keeps `swimlanes`
  # from blowing up.
  def groupable_columns
    super.reject { |column| column.is_a?(QueryCustomFieldColumn) }
  end

  # --- Board scope ---------------------------------------------------

  # The issues considered by this board, before column/swimlane bucketing.
  def board_scope
    base_scope
      .eager_load(:status, :project, :assigned_to, :tracker, :priority, :fixed_version,
                  :expert_agile_data)
      .where(:status_id => board_columns.map(&:id))
  end

  # --- Columns of the board ------------------------------------------

  def board_columns
    @board_columns ||= begin
      counts = issue_count_by_status
      hours = estimated_hours_by_status
      points = story_points_by_status
      limits = wip_limits

      board_statuses.map do |status|
        min, max = limits[status.id]
        RedmineExpertAgile::BoardColumn.new(
          :status => status,
          :issue_count => counts[status.id].to_i,
          :estimated_hours => hours[status.id],
          :story_points => points[status.id],
          :wip_min => min,
          :wip_max => max
        )
      end
    end
  end

  # Statuses shown as columns, in Redmine's own status order.
  #
  # Scoped to the statuses this project's trackers can actually reach, via
  # Redmine's own Project#rolled_up_statuses. Falling back to every open status
  # in the instance produces a board of dozens of permanently empty columns —
  # on a real installation that is 37 columns of which 3 are used, squeezed to
  # 27px each.
  #
  # Closed statuses are excluded unless explicitly selected: a board is about
  # work in flight. The "done" column is whichever closed status the project
  # picks in the board settings.
  def board_statuses
    @board_statuses ||= begin
      selected = board_status_ids
      if selected.any?
        IssueStatus.where(:id => selected).sorted.to_a
      else
        default_board_statuses
      end
    end
  end

  private

  def default_board_statuses
    scope = project ? project.rolled_up_statuses : IssueStatus.sorted
    statuses = scope.reject(&:is_closed?)

    # A project whose workflows define no transitions would otherwise render a
    # board with no columns at all; fall back to the statuses actually in use.
    if statuses.empty?
      used_ids = base_scope.reorder(nil).distinct.pluck(:status_id)
      statuses = IssueStatus.where(:id => used_ids).sorted.to_a
    end
    statuses
  end

  # base_scope already joins :status and :project, so grouping needs no extra
  # join — status_id is a column on issues itself.
  def grouped_issue_count(select_sql = nil)
    scope = base_scope.reorder(nil).group("#{Issue.table_name}.status_id")
    select_sql ? scope.sum(select_sql) : scope.count
  end

  def issue_count_by_status
    @issue_count_by_status ||= grouped_issue_count
  end

  def estimated_hours_by_status
    @estimated_hours_by_status ||= grouped_issue_count("#{Issue.table_name}.estimated_hours")
  end

  def story_points_by_status
    @story_points_by_status ||=
      base_scope.reorder(nil)
                .joins("LEFT OUTER JOIN #{ExpertAgileData.table_name} ead " \
                       "ON ead.issue_id = #{Issue.table_name}.id")
                .group("#{Issue.table_name}.status_id")
                .sum('ead.story_points')
  end
end
