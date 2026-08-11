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

  # Statuses offerable as board columns: everything the project's workflows can
  # reach, closed ones included — a board usually wants exactly one "done"
  # column, and which status that is, only the project knows.
  def expert_agile_selectable_statuses(query)
    scope = query.project ? query.project.rolled_up_statuses : IssueStatus.sorted
    statuses = scope.to_a
    # Anything already configured as a column stays selectable even if the
    # workflow changed underneath it, so the panel never silently drops a column.
    (statuses + query.board_statuses).uniq.sort_by { |s| [s.position.to_i, s.id] }
  end

  # Renders one card field through Redmine's own column_content, so custom
  # fields, list values, users and dates all format exactly as they do in the
  # issue list. Falls back to the raw value if a column raises — one awkward
  # custom field must not take the whole board down.
  def expert_agile_card_value(column, issue)
    # The board's own field: there is no Issue#day_in_state for column_content
    # to call, the value comes from the board's grouped journal lookup.
    return expert_agile_days_in_status_label(issue) if column.name == :day_in_state

    column_content(column, issue)
  rescue StandardError
    value = column.value_object(issue) rescue nil
    value.is_a?(Array) ? value.join(', ') : value.to_s
  end

  def expert_agile_days_in_status_label(issue)
    days = @query.days_in_status(issue)
    return nil if days.nil?

    days.zero? ? l(:label_expert_agile_today) : l(:label_expert_agile_days_count, :count => days)
  end

  # A plain-text opening of the description, for the card.
  #
  # Deliberately not textilizable: a card is a summary, and rendering full
  # wiki markup inside one drags in headings, tables and images that break the
  # card layout.
  def expert_agile_description_excerpt(issue)
    text = issue.description.to_s.strip
    return nil if text.blank?

    text = text.gsub(/<[^>]*>/, ' ')              # HTML — descriptions ingested
                                                  # from email are full of it
               .gsub(/!\S+!/, '')                 # inline image macros
               .gsub(/\{\{[^}]*\}\}/, '')         # wiki macros
               .gsub(/[*_+\-#>|]+/, ' ')          # textile decoration
               .gsub(/\s+/, ' ')
               .strip
    # No :separator. Breaking on whitespace looks tidier until the text
    # contains a long unbroken token — an email address or a URL, which is
    # exactly what a forwarded mail starts with — and then the last space
    # before the limit is near the beginning and the excerpt collapses to a
    # few characters.
    truncate(text, :length => RedmineExpertAgile.card_description_length)
  end

  # Accent colour for one swimlane, so adjacent lanes are told apart at a
  # glance rather than all sharing one hue.
  #
  # A lane that carries its own colour — a tracker, priority or status the
  # administrator has coloured — uses it, so the lane matches its cards.
  # Anything else gets a stable palette entry derived from its id.
  def expert_agile_swimlane_color_class(swimlane)
    return 'ea-lane-gray' if swimlane.nil?

    colour = RedmineExpertAgile::CardColor.for_container(swimlane)
    colour.present? ? "ea-lane-#{colour}" : 'ea-lane-gray'
  end

  # Saved boards (or charts) visible to the current user in this scope.
  #
  # Filtered to the exact STI type: ExpertAgileChartsQuery and
  # ExpertAgileBacklogQuery are subclasses of ExpertAgileQuery, so an
  # unqualified lookup would list charts among the boards.
  def expert_agile_saved_queries(klass)
    scope = klass.where(:type => klass.name).visible
    scope = scope.global_or_on_project(@project) if @project
    scope.sorted.to_a
  end

  def board_path_for(project)
    project ? project_expert_agile_board_path(project) : expert_agile_board_path
  end

  # The `new` action, not the collection path: the save link re-submits the
  # board form to it so the configuration the user is looking at arrives with
  # the request. Pointing at the collection path GETs #index, which just
  # redirects back to the board and loses everything.
  def new_board_path_for(project)
    project ? new_project_expert_agile_query_path(project) : new_expert_agile_query_path
  end

  # Palette class for a column header, so the board reads as a set of stages at
  # a glance. Only applied when the setting is on and the cell is a leaf.
  def expert_agile_status_color_class(column)
    return nil unless column && RedmineExpertAgile.status_colors?

    color = RedmineExpertAgile::CardColor.for_status(column.status)
    color.present? ? "ea-status-#{color}" : nil
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
