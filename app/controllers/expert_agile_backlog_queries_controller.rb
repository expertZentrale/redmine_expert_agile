# Saving, editing and deleting backlogs.
#
# A saved backlog is an ExpertAgileBacklogQuery, which is an ExpertAgileQuery
# with a container kind — so this is the board's query controller pointed at a
# different class rather than a third copy of it, exactly as the charts variant
# is.
class ExpertAgileBacklogQueriesController < ExpertAgileQueriesController
  menu_item :expert_agile_backlog

  private

  def query_class
    ExpertAgileBacklogQuery
  end

  # The backlog is project-scoped only — there is no global planner — so a saved
  # backlog always has a project and this always resolves. The fallback is there
  # so a stray global row cannot raise a routing error on delete.
  def board_path(options = {})
    @project ? project_expert_agile_backlog_path(@project, options) : home_path
  end

  def query_collection_path
    if @project
      project_expert_agile_backlog_queries_path(@project)
    else
      expert_agile_backlog_queries_path
    end
  end

  def query_member_path(query)
    expert_agile_backlog_query_path(query)
  end

  def query_page_title
    l(:label_expert_agile_backlog_new)
  end

  def query_options_partial
    'expert_agile_backlogs/backlog_options'
  end
end
