module ExpertAgileBoardsHelper
  # Groups board columns into the header rows that render sub-columns.
  #
  # Sub-columns are a naming convention: statuses called "Dev: Review" and
  # "Dev: Test" nest under one "Dev" header. Returns an array of rows, each a
  # list of {:label, :colspan, :rowspan, :column} cells, where :column is set
  # only on leaf cells.
  #
  # Only *adjacent* runs are merged. RedmineUP keys header nodes by name and
  # only checks the last one, so two "Dev:" columns separated by an unrelated
  # column produce two separate "Dev" headers that look like a rendering bug.
  # Merging runs keeps the column order the user configured and makes the
  # grouping predictable.
  def expert_agile_header_rows(columns)
    depth = columns.map { |column| column.path.size }.max.to_i
    depth = 1 if depth < 1
    return [columns.map { |column| header_cell(column, 1, 1) }] if depth == 1

    rows = Array.new(depth) { [] }
    runs_of(columns).each do |prefix, run|
      if prefix.nil?
        # No prefix: the column spans every header row.
        run.each { |column| rows[0] << header_cell(column, 1, depth) }
      else
        rows[0] << { :label => prefix, :colspan => run.size, :rowspan => 1, :column => nil }
        run.each { |column| rows[1] << header_cell(column, 1, depth - 1) }
      end
    end
    rows.reject(&:empty?)
  end

  # CSS classes for one card.
  def expert_agile_card_classes(issue, query)
    classes = ['ea-card', "ea-card-tracker-#{issue.tracker_id}"]
    classes << 'ea-card-closed' if issue.closed?
    classes << 'ea-card-overdue' if issue.overdue?
    classes << 'ea-card-private' if issue.is_private?
    classes << expert_agile_color_class(issue, query)
    classes.compact.join(' ')
  end

  # Palette class for one card, or nil when the board is not coloured.
  def expert_agile_color_class(issue, query)
    base = query && query.color_base
    return nil if base.blank? || base == 'none'

    color = RedmineExpertAgile::CardColor.for(issue, base)
    color.present? ? "ea-color-#{color}" : nil
  end

  # The data the board script needs, emitted as a JSON island rather than
  # inline JavaScript so the board works under `script-src 'self'`.
  def expert_agile_board_data(query, project)
    {
      :mode => 'board',
      :dropParam => 'status_id',
      :updateUrlTemplate => update_expert_agile_board_issue_path(:id => '__ID__'),
      :tooltipUrlTemplate => expert_agile_board_issue_tooltip_path(:id => '__ID__'),
      :queryId => query.id,
      :projectId => project&.id,
      :editable => User.current.allowed_to?(:edit_expert_agile_board, project, :global => project.nil?),
      :columns => query.board_columns.map(&:to_h),
      :labels => {
        :wipExceeded => l(:text_expert_agile_wip_limit_exceeded),
        :moveFailed => l(:error_expert_agile_status_transition_not_allowed)
      }
    }.to_json
  end

  private

  def header_cell(column, colspan, rowspan)
    { :label => column.leaf_name, :colspan => colspan, :rowspan => rowspan, :column => column }
  end

  # [[prefix_or_nil, [columns...]], ...] over adjacent columns sharing a prefix.
  def runs_of(columns)
    columns.chunk_while do |a, b|
      a.path.size > 1 && b.path.size > 1 && a.path.first == b.path.first
    end.map do |run|
      prefix = run.size >= 1 && run.first.path.size > 1 ? run.first.path.first : nil
      [prefix, run]
    end
  end
end
