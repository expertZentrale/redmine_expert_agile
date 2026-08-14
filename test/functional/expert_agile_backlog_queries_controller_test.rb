require File.expand_path('../../test_helper', __FILE__)

# Saving a backlog.
#
# The controller, the routes and the permissions are shared with the board and
# the chart variants; the class that ends up in the queries table is not. The
# shared new/edit templates used to hardcode the board's routes, which silently
# turned a saved chart into a saved board — so where each variant posts is
# asserted here rather than assumed.
class ExpertAgileBacklogQueriesControllerTest < Redmine::ControllerTest
  tests ExpertAgileBacklogQueriesController

  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :enabled_modules, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :issues, :versions, :queries

  def setup
    @project = Project.find(1)
    @project.enable_module!(:expert_agile)
    @project.enable_module!(:expert_agile_backlog)
    @role = Role.find(1)
    @role.add_permission!(:view_expert_agile_backlog, :add_expert_agile_queries)
    @request.session[:user_id] = 2
  end

  def backlog!(attributes = {})
    query = ExpertAgileBacklogQuery.new({ :name => 'Planner', :project => @project,
                                          :user => User.find(2),
                                          :visibility => Query::VISIBILITY_PRIVATE }
                                          .merge(attributes))
    query.save!
    query
  end

  # --- Creating ---------------------------------------------------------

  def test_create_saves_a_backlog_and_returns_to_the_planner
    assert_difference 'ExpertAgileBacklogQuery.count', 1 do
      post :create, :params => { :project_id => @project.id,
                                 :query => { :name => 'Version planning' },
                                 :container_type => 'version' }
    end

    query = ExpertAgileBacklogQuery.order(:id).last
    assert_redirected_to project_expert_agile_backlog_path(@project, :query_id => query.id)
    assert_equal 'Version planning', query.name
    assert_equal 'version', query.container_type
  end

  def test_a_saved_backlog_is_its_own_type
    post :create, :params => { :project_id => @project.id,
                               :query => { :name => 'Sprint planning' },
                               :container_type => 'sprint' }

    assert_equal 1, ExpertAgileBacklogQuery.where(:type => 'ExpertAgileBacklogQuery').count
    assert_equal 0, ExpertAgileQuery.where(:type => 'ExpertAgileQuery').count,
                    'a backlog must not be stored as a board'
  end

  def test_create_keeps_the_filters_from_the_panel
    post :create, :params => { :project_id => @project.id,
                               :query => { :name => 'Mine' },
                               :container_type => 'sprint',
                               :f => ['assigned_to_id'], :op => { 'assigned_to_id' => '=' },
                               :v => { 'assigned_to_id' => ['me'] } }

    assert_equal ['assigned_to_id'], ExpertAgileBacklogQuery.order(:id).last.filters.keys
  end

  def test_create_requires_the_permission
    @role.remove_permission!(:add_expert_agile_queries)

    assert_no_difference 'ExpertAgileBacklogQuery.count' do
      post :create, :params => { :project_id => @project.id, :query => { :name => 'Nope' } }
    end

    assert_response :forbidden
  end

  # --- The form ---------------------------------------------------------

  def test_new_posts_to_the_backlog_variant
    get :new, :params => { :project_id => @project.id, :container_type => 'version' }

    assert_response :success
    assert_select 'form[action=?]', project_expert_agile_backlog_queries_path(@project)
    assert_select 'input[type=hidden][name=?][value=?]', 'container_type', 'version'
  end

  def test_edit_posts_to_the_backlog_variant
    query = backlog!

    get :edit, :params => { :id => query.id }

    assert_response :success
    assert_select 'form[action=?]', expert_agile_backlog_query_path(query)
  end

  # --- Updating and deleting --------------------------------------------

  def test_update_changes_the_container_type
    query = backlog!

    put :update, :params => { :id => query.id, :query => { :name => 'Planner' },
                              :container_type => 'version' }

    assert_redirected_to project_expert_agile_backlog_path(@project, :query_id => query.id)
    assert_equal 'version', query.reload.container_type
  end

  def test_destroy_returns_to_the_planner
    query = backlog!

    assert_difference 'ExpertAgileBacklogQuery.count', -1 do
      delete :destroy, :params => { :id => query.id }
    end

    assert_redirected_to project_expert_agile_backlog_path(@project)
  end

  def test_another_users_private_backlog_cannot_be_edited
    query = backlog!(:user => User.find(3))

    get :edit, :params => { :id => query.id }

    assert_response :forbidden
  end
end
