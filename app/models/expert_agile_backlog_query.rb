# The backlog planner: an unplanned backlog plus one lane per container.
#
# Parameterised over the container kind rather than duplicated per kind.
# RedmineUP ships AgileSprintsQuery and AgileVersionsQuery, ~10 KB each and
# ~90% identical; everything that actually differs between planning into a
# sprint and planning into a version is isolated in the four small methods at
# the bottom of this class.
class ExpertAgileBacklogQuery < ExpertAgileQuery
  # Reading a saved backlog needs the backlog permission, not the board one it
  # would otherwise inherit — the two are separate project modules, so a project
  # may well have one without the other.
  self.view_permission = :view_expert_agile_backlog

  # STI guard for our own listings, as on the board and the charts.
  scope :only_backlogs, -> { where(:type => name) }

  CONTAINER_SPRINT = 'sprint'.freeze
  CONTAINER_VERSION = 'version'.freeze
  CONTAINER_EPIC = 'epic'.freeze
  CONTAINER_TYPES = [CONTAINER_SPRINT, CONTAINER_VERSION, CONTAINER_EPIC].freeze

  # Epics are a container only while some tracker is an epic tracker; a
  # backlog saved for epics falls back to sprints once they are switched off.
  def self.container_types
    RedmineExpertAgile::Epics.enabled? ? CONTAINER_TYPES : CONTAINER_TYPES - [CONTAINER_EPIC]
  end

  # Which containers are being planned into is display state like any other
  # panel setting, so it has to survive a request the same way.
  def self.session_option_keys
    super + [:container_type]
  end

  def container_type
    value = options[:container_type].to_s
    self.class.container_types.include?(value) ? value : CONTAINER_SPRINT
  end

  def container_type=(value)
    options[:container_type] = self.class.container_types.include?(value.to_s) ? value.to_s : CONTAINER_SPRINT
  end

  def sprints?
    container_type == CONTAINER_SPRINT
  end

  def epics?
    container_type == CONTAINER_EPIC
  end

  # The planner's epic lanes show their progress, like the board's.
  def epics_on_screen
    epics? ? containers : []
  end

  # The planner's own part of the options panel. Redmine's build_from_params
  # covers filters, card fields and sorting; the inherited implementation covers
  # colouring and the avatar. Only the container kind is left.
  #
  # The board settings the parent also reads — status columns, WIP limits — are
  # inert here: the panel never offers them and `planning_scope` ignores where an
  # issue sits in the workflow.
  def apply_board_params(params)
    super
    self.container_type = params[:container_type] if params[:container_type].present?
    self
  end

  # The lanes to plan into, in planning order.
  def containers
    @containers ||= if sprints?
                      available_sprints
                    elsif epics?
                      available_epics
                    else
                      available_versions
                    end
  end

  # Issues already planned into one container, in board rank order.
  def issues_for(container)
    return [] if container.nil?

    planned_scope(container).sorted_by_rank.limit(RedmineExpertAgile.board_items_limit).to_a
  end

  # Everything not planned into any container yet.
  def backlog_issues(term = nil)
    scope = unplanned_scope
    scope = filter_by_term(scope, term) if term.present?
    scope.sorted_by_rank.limit(RedmineExpertAgile.board_items_limit).to_a
  end

  # Aggregates shown in a lane header.
  def totals_for(container)
    scope = container.nil? ? unplanned_scope : planned_scope(container)
    {
      :issue_count => scope.count,
      :estimated_hours => scope.sum(:estimated_hours),
      :story_points => ExpertAgileData.where(:issue_id => scope.select(:id)).sum(:story_points)
    }
  end

  # The scope a planning move ranks within, used when a rebalance is needed.
  def siblings_for(container)
    container.nil? ? unplanned_scope.sorted_by_rank : planned_scope(container).sorted_by_rank
  end

  # Resolves an id from the request to a container this project may plan into.
  # Returning nil for anything else is what keeps a crafted id from moving an
  # issue into a sprint of an unrelated project.
  def container_for(id)
    return nil if id.blank?

    containers.detect { |container| container.id.to_s == id.to_s }
  end

  private

  # The planner ignores the board's status columns: an issue is planned
  # regardless of where it sits in the workflow.
  def planning_scope
    base_scope.eager_load(:status, :tracker, :priority, :assigned_to, :expert_agile_data)
  end

  def filter_by_term(scope, term)
    if term.to_s =~ /\A#?(\d+)\z/
      scope.where(:id => Regexp.last_match(1))
    else
      # % and _ in the term are literal characters, not wildcards.
      pattern = "%#{Issue.sanitize_sql_like(term.to_s.downcase)}%"
      scope.where("LOWER(#{Issue.table_name}.subject) LIKE ?", pattern)
    end
  end

  # --- The only container-specific parts ------------------------------

  def available_sprints
    project ? project.shared_expert_agile_sprints.available.sorted.to_a : []
  end

  def available_versions
    project ? project.shared_versions.open.sorted.to_a : []
  end

  # Open epics of the project and its subprojects that the user may see, by
  # subject. Planning into an epic makes the issue its subtask, so an epic
  # from elsewhere is refused by the issue's own validation if it must be.
  def available_epics
    return [] unless project

    Issue.visible.open
         .where(:tracker_id => RedmineExpertAgile::Epics.tracker_ids)
         .where(:project_id => project.self_and_descendants.select(:id))
         .order(:subject).to_a
  end

  # Planning into epics moves stories: issues straight under an epic, or
  # under nothing. A story's subtasks follow their story, and the epics are
  # the lanes, so neither is a card here.
  def epic_planning_scope
    planning_scope.where.not(:tracker_id => RedmineExpertAgile::Epics.tracker_ids)
  end

  def planned_scope(container)
    if epics?
      epic_planning_scope.where(:parent_id => container.id)
    elsif sprints?
      planning_scope.joins(:expert_agile_data)
                    .where(ExpertAgileData.table_name => { :sprint_id => container.id })
    else
      planning_scope.where(:fixed_version_id => container.id)
    end
  end

  def unplanned_scope
    if epics?
      epic_planning_scope.where(:parent_id => nil)
    elsif sprints?
      planning_scope.where(
        "#{Issue.table_name}.id NOT IN (SELECT issue_id FROM #{ExpertAgileData.table_name} " \
        'WHERE sprint_id IS NOT NULL)'
      )
    else
      planning_scope.where(:fixed_version_id => nil)
    end
  end
end
