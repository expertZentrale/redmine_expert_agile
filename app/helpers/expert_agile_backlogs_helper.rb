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
end
