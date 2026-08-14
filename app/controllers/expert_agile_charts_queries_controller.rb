# Saving, editing and deleting charts.
#
# A saved chart is an ExpertAgileChartsQuery, which is an ExpertAgileQuery with
# a chart selection and a date range — so this is the board's query controller
# pointed at a different class rather than a second copy of it.
class ExpertAgileChartsQueriesController < ExpertAgileQueriesController
  menu_item :expert_agile_charts

  private

  def query_class
    ExpertAgileChartsQuery
  end

  def board_path(options = {})
    if @project
      project_expert_agile_charts_path(@project, options)
    else
      expert_agile_charts_path(options)
    end
  end

  def query_collection_path
    if @project
      project_expert_agile_charts_queries_path(@project)
    else
      expert_agile_charts_queries_path
    end
  end

  def query_member_path(query)
    expert_agile_charts_query_path(query)
  end

  def query_page_title
    l(:label_expert_agile_chart_new)
  end
end
