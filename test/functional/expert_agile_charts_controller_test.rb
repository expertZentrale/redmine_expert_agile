require File.expand_path('../../test_helper', __FILE__)

# The charts page. What matters here is which saved chart a query_id may open:
# it used to be looked up without `visible`, so another user's private chart
# opened by id, with its name, filters and date range.
class ExpertAgileChartsControllerTest < Redmine::ControllerTest
  tests ExpertAgileChartsController

  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :enabled_modules, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :issues, :queries

  def setup
    @project = Project.find(1)
    @project.enable_module!(:expert_agile)
    Role.find(1).add_permission!(:view_expert_agile_board, :view_expert_agile_charts)
    @request.session[:user_id] = 2
  end

  def chart_query!(attributes)
    query = ExpertAgileChartsQuery.new({ :project => @project, :name => 'Chart' }.merge(attributes))
    query.chart = 'burndown'
    query.save!
    query
  end

  def test_another_users_private_chart_does_not_open
    private_chart = chart_query!(:name => 'Their private chart', :user => User.find(3),
                                 :visibility => Query::VISIBILITY_PRIVATE)

    get :show, :params => { :project_id => @project.id, :query_id => private_chart.id }

    assert_response :not_found
  end

  def test_a_public_chart_opens
    public_chart = chart_query!(:name => 'Team burndown', :user => User.find(3),
                                :visibility => Query::VISIBILITY_PUBLIC)

    get :show, :params => { :project_id => @project.id, :query_id => public_chart.id }

    assert_response :success
  end

  def test_the_users_own_private_chart_opens
    own = chart_query!(:name => 'Mine', :user => User.find(2),
                       :visibility => Query::VISIBILITY_PRIVATE)

    get :show, :params => { :project_id => @project.id, :query_id => own.id }

    assert_response :success
  end

  # `only_charts` pins the STI type: a board's id must not open as a chart.
  def test_a_board_id_does_not_open_as_a_chart
    board = ExpertAgileQuery.create!(:project => @project, :name => 'Board', :user => User.find(2),
                                     :visibility => Query::VISIBILITY_PUBLIC)

    get :show, :params => { :project_id => @project.id, :query_id => board.id }

    assert_response :not_found
  end

  # The x axis has one bucket per interval step. An unbounded range made one
  # request compute millions of buckets.
  def test_an_absurd_date_range_is_clamped
    get :render_chart, :params => { :project_id => @project.id, :chart => 'burndown',
                                    :interval => 'day',
                                    :date_from => '0001-01-01', :date_to => '2026-01-31' },
                       :xhr => true, :format => :js

    assert_response :success
    labels = JSON.parse(response.body)['labels']
    assert labels, 'the chart must still render'
    assert_operator labels.size, :<=, ExpertAgileChartsQuery::MAX_RANGE_DAYS + 1
  end
end
