require File.expand_path('../../test_helper', __FILE__)

# Saving a chart. The routes and permissions for this existed from the first
# commit with no controller behind them, exactly as happened with saved boards
# — so it gets its own tests rather than being assumed to work.
class ExpertAgileChartsQueriesControllerTest < Redmine::ControllerTest
  tests ExpertAgileChartsQueriesController

  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :enabled_modules, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :issues, :queries

  def setup
    @project = Project.find(1)
    @project.enable_module!(:expert_agile)
    Role.find(1).add_permission!(:view_expert_agile_board, :view_expert_agile_charts,
                                 :add_expert_agile_queries)
    @request.session[:user_id] = 2
  end

  def test_create_saves_a_chart_and_returns_to_the_charts_page
    assert_difference 'ExpertAgileChartsQuery.count', 1 do
      post :create, :params => { :project_id => @project.id,
                                 :query => { :name => 'Sprint burndown' },
                                 :chart => 'burnup', :chart_unit => 'story_points',
                                 :interval => 'week',
                                 :date_from => '2026-01-01', :date_to => '2026-01-31' }
    end

    query = ExpertAgileChartsQuery.order(:id).last
    assert_redirected_to project_expert_agile_charts_path(@project, :query_id => query.id)
    assert_equal 'Sprint burndown', query.name
  end

  def test_saved_chart_keeps_its_selection
    post :create, :params => { :project_id => @project.id,
                               :query => { :name => 'Velocity' },
                               :chart => 'velocity', :interval => 'week',
                               :date_from => '2026-02-01', :date_to => '2026-02-28' }

    reloaded = ExpertAgileChartsQuery.find(ExpertAgileChartsQuery.order(:id).last.id)
    assert_equal 'velocity', reloaded.chart
    assert_equal 'week', reloaded.interval
    assert_equal Date.new(2026, 2, 1), reloaded.date_from
    assert_equal Date.new(2026, 2, 28), reloaded.date_to
  end

  def test_saved_charts_are_a_separate_list_from_boards
    post :create, :params => { :project_id => @project.id,
                               :query => { :name => 'A chart' }, :chart => 'burndown' }

    assert_equal 1, ExpertAgileChartsQuery.where(:type => 'ExpertAgileChartsQuery').count
    assert_equal 0, ExpertAgileQuery.where(:type => 'ExpertAgileQuery').count,
                 'a saved chart must not show up among the boards'
  end
end
