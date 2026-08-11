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
      :projectId => project.id,
      :editable => User.current.allowed_to?(:manage_expert_agile_backlog, project),
      :labels => {
        :moveFailed => l(:error_expert_agile_container_not_available)
      }
    }.to_json
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
