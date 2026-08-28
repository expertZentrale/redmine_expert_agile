module ExpertAgileBacklogsHelper
  # Configuration for the shared drag & drop script, in the same shape the
  # board emits. Only the endpoint and the parameter name differ, which is what
  # lets one script drive both screens — RedmineUP ships two divergent
  # initSortable implementations with different payloads.
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
      :labels => {
        :moveFailed => l(:error_expert_agile_move_failed),
        # A refusal with no body to carry its reason: Redmine answers a missing
        # permission and an expired session with an empty 403 / 401.
        :notPermitted => l(:error_expert_agile_move_not_permitted),
        :sessionExpired => l(:error_expert_agile_session_expired),
        # For the one failure that is not a refusal: the server saved the move
        # and the board could not show it.
        :saveNotShown => l(:error_expert_agile_move_saved_but_not_shown)
      }
    }.to_json
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
