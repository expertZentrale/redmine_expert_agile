module ExpertAgileBacklogsHelper
  # Configuration for the shared drag & drop script, in the same shape the
  # board emits. Only the endpoint and the parameter name differ, which is what
  # lets one script drive both screens.
  def expert_agile_backlog_data(query, project)
    {
      :mode => 'backlog',
      :dropParam => 'container_id',
      :updateUrlTemplate => update_expert_agile_backlog_issue_path(:project_id => project,
                                                                   :id => '__ID__'),
      :containerType => query.container_type,
      # A move ranks the card within its lane, and the lane is what the filters
      # select — so the planning request has to arrive at the same backlog the
      # user is looking at, saved one included.
      :queryId => query.id,
      :projectId => project.id,
      :editable => User.current.allowed_to?(:manage_expert_agile_backlog, project),
      # Where a card dropped onto an epic of the epic panel goes; nil while
      # the planner shows no panel.
      :epicUpdateUrlTemplate => (if query.epic_panel?
                                   update_epic_expert_agile_backlog_issue_path(:project_id => project,
                                                                               :id => '__ID__')
                                 end),
      # The planner as it is on screen, sent with every move: a saved planner
      # can be tweaked for the page (an epic chosen on the panel), and the
      # answer's totals and whether the card still shows have to be worked
      # out against that, not against the planner as saved.
      :stateParams => expert_agile_planner_state_params(query),
      # Which lanes are folded is remembered per browser, apart for every
      # planner kind: a sprint and a version may share an id.
      :laneStoragePrefix => "expert_agile.planner.#{project.id}.#{query.container_type}",
      :labels => {
        :moveFailed => l(:error_expert_agile_move_failed),
        # A refusal with no body to carry its reason: Redmine answers a missing
        # permission and an expired session with an empty 403 / 401.
        :notPermitted => l(:error_expert_agile_move_not_permitted),
        :sessionExpired => l(:error_expert_agile_session_expired),
        # For the one failure that is not a refusal: the server saved the move
        # and the board could not show it.
        :saveNotShown => l(:error_expert_agile_move_saved_but_not_shown),
        # A card the epic panel moved out of the epic the planner is filtered
        # to: saved, and gone from the screen.
        :cardHiddenByFilter => l(:text_expert_agile_card_hidden_by_filter),
        :collapse => l(:label_expert_agile_lane_collapse),
        :expand => l(:label_expert_agile_lane_expand),
        # A change made through the issue context menu: the same refusals as
        # a move, in words that do not speak of moving a card.
        :changeFailed => l(:error_expert_agile_change_failed),
        :changeNotPermitted => l(:error_expert_agile_change_not_permitted),
        :boardNotRefreshed => l(:error_expert_agile_board_not_refreshed)
      }
    }.to_json
  end

  # The epic filter an entry of the epic panel stands for: one epic, no epic
  # (nil for "all issues" — no epic filter at all).
  def expert_agile_epic_panel_filter(epic)
    case epic
    when :none then { :operator => '!*', :values => [''] }
    when Issue then { :operator => '=', :values => [epic.id.to_s] }
    end
  end

  # Which entry the planner's epic filter currently matches: :all, :none, an
  # epic id, or nil when the filter is set to something the panel has no entry
  # for (several epics, "not this epic").
  def expert_agile_epic_panel_selection(query)
    return :all unless query.has_filter?('expert_agile_epic_id')

    operator = query.operator_for('expert_agile_epic_id')
    values = Array(query.values_for('expert_agile_epic_id')).reject(&:blank?)
    return :none if operator == '!*'
    return values.first.to_i if operator == '=' && values.size == 1

    nil
  end

  # The planner as it is, with the epic filter of one panel entry in place
  # of its own: every other filter, the card fields, the colours and the
  # layout stay.
  def expert_agile_epic_panel_params(query, entry)
    filters = query.filters.reject { |field, _| field == 'expert_agile_epic_id' }
    epic_filter = expert_agile_epic_panel_filter(entry)
    filters = filters.merge('expert_agile_epic_id' => epic_filter) if epic_filter
    expert_agile_planner_state_params(query, filters)
  end

  # Everything that makes up the planner on screen, as request parameters
  # (by default with its own filters). A saved planner keeps its id, so the
  # parameters tweak it for one request the way Apply does, without writing
  # anything back.
  def expert_agile_planner_state_params(query, filters = query.filters)
    params = {
      :set_filter => '1',
      :container_type => query.container_type,
      :planner_layout => query.planner_layout,
      :color_base => query.color_base,
      :show_avatar => query.show_avatar? ? '1' : '0',
      # The trailing blank keeps the list present when no filter is left, so
      # Redmine applies none rather than its defaults.
      :f => filters.keys + [''],
      :op => filters.each_with_object({}) { |(field, filter), acc| acc[field] = filter[:operator] },
      :v => filters.each_with_object({}) { |(field, filter), acc| acc[field] = filter[:values] },
      :c => Array(query.column_names).map(&:to_s)
    }
    params[:query_id] = query.id if query.persisted?
    params
  end

  # The planner has the same reach as the board — a project's backlog carries
  # its subprojects' issues — so whether a card may be planned is a question
  # about that card's own project. See the board helper's copy.
  def expert_agile_planning_card_movable?(issue)
    project = issue.project
    return false if project.nil?

    @expert_agile_plannable_projects ||= {}
    @expert_agile_plannable_projects.fetch(project.id) do
      @expert_agile_plannable_projects[project.id] =
        User.current.allowed_to?(:manage_expert_agile_backlog, project)
    end
  end

  def backlog_path_for(project, options = {})
    project_expert_agile_backlog_path(project, options)
  end

  # The `new` action, not the collection path: the save link re-submits the
  # panel to it so the configuration the user is looking at arrives with the
  # request. Pointing at the collection path GETs #index, which just redirects
  # back to the backlog and loses everything.
  def new_backlog_query_path_for(project)
    new_project_expert_agile_backlog_query_path(project)
  end

  # Dates and lifecycle for a planning lane's subtitle.
  #
  # Sprints and versions carry different date fields, which is the one place
  # the parameterised planner still has to know which kind it is dealing with.
  def expert_agile_container_meta(container)
    return nil if container.nil?

    if container.is_a?(ExpertAgileSprint)
      parts = ["#{format_date(container.start_date)} – #{format_date(container.end_date)}"]
      remaining = container.remaining_days
      parts << l(:label_expert_agile_days_remaining, :count => remaining) if remaining && remaining > 0
      safe_join([
        content_tag(:span, l("label_expert_agile_sprint_status_#{container.status_name}"),
                    :class => "ea-backlog-status ea-sprint-#{container.status_name}"),
        ' ',
        parts.join(' · ')
      ])
    elsif container.respond_to?(:effective_date) && container.effective_date.present?
      format_date(container.effective_date)
    end
  end

  # The backlog reuses the board's card colouring and drop-target markup, so
  # its helper comes along too.
  def self.included(base)
    base.send(:include, ExpertAgileBoardsHelper) unless base.include?(ExpertAgileBoardsHelper)
  end
end
