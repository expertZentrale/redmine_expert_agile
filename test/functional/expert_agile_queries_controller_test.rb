require File.expand_path('../../test_helper', __FILE__)

# Saving a board. These routes and permissions existed from the first commit
# but the controller did not, so "save this board" 404'd and nothing noticed.
class ExpertAgileQueriesControllerTest < Redmine::ControllerTest
  tests ExpertAgileQueriesController

  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :enabled_modules, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :issues, :queries

  def setup
    @project = Project.find(1)
    @project.enable_module!(:expert_agile)
    @role = Role.find(1)
    @role.add_permission!(:view_expert_agile_board, :add_expert_agile_queries,
                          :manage_public_expert_agile_queries)
    @request.session[:user_id] = 2
    @status_id = Issue.find(1).status_id
  end

  def board_params(extra = {})
    {
      :project_id => @project.id,
      :query => { :name => 'My board', :visibility => Query::VISIBILITY_PRIVATE.to_s },
      :board_status_ids => [@status_id.to_s],
      :wip_limits => { @status_id.to_s => ['2', '5'] },
      :color_base => 'priority',
      :show_avatar => '0',
      :group_by => 'tracker',
      :c => %w(status priority)
    }.merge(extra)
  end

  def test_create_saves_the_board_configuration
    assert_difference 'ExpertAgileQuery.count', 1 do
      post :create, :params => board_params
    end

    query = ExpertAgileQuery.order(:id).last
    assert_redirected_to project_expert_agile_board_path(@project, :query_id => query.id)

    assert_equal 'My board', query.name
    # The whole point of the complaint that prompted these tests: the WIP
    # limits have to come back after a round trip through the database.
    assert_equal [2, 5], query.wip_limits[@status_id]
    assert_equal [@status_id], query.board_status_ids
    assert_equal 'priority', query.color_base
    assert_equal 'tracker', query.group_by
    assert_not query.show_avatar?
  end

  def test_saved_configuration_survives_a_reload_from_the_database
    post :create, :params => board_params
    query = ExpertAgileQuery.order(:id).last

    reloaded = ExpertAgileQuery.find(query.id)

    assert_equal [2, 5], reloaded.wip_limits[@status_id]
    assert_equal [@status_id], reloaded.board_status_ids
    assert_equal 'priority', reloaded.color_base
    assert_not reloaded.show_avatar?
  end

  def test_update_changes_the_configuration
    post :create, :params => board_params
    query = ExpertAgileQuery.order(:id).last

    put :update, :params => { :id => query.id,
                              :query => { :name => 'Renamed' },
                              :board_status_ids => [@status_id.to_s],
                              :wip_limits => { @status_id.to_s => ['', '9'] },
                              :color_base => 'tracker' }

    reloaded = ExpertAgileQuery.find(query.id)
    assert_equal 'Renamed', reloaded.name
    assert_equal [nil, 9], reloaded.wip_limits[@status_id]
    assert_equal 'tracker', reloaded.color_base
  end

  def test_destroy
    post :create, :params => board_params
    query = ExpertAgileQuery.order(:id).last

    assert_difference 'ExpertAgileQuery.count', -1 do
      delete :destroy, :params => { :id => query.id }
    end
    assert_redirected_to project_expert_agile_board_path(@project)
  end

  def test_public_visibility_is_ignored_without_the_manage_permission
    # Matches Redmine's own behaviour: the visibility attribute is simply not
    # assignable, so the board is saved as private rather than rejected.
    @role.remove_permission!(:manage_public_expert_agile_queries)

    assert_difference 'ExpertAgileQuery.count', 1 do
      post :create, :params => board_params(
        :query => { :name => 'Public', :visibility => Query::VISIBILITY_PUBLIC.to_s }
      )
    end

    assert ExpertAgileQuery.order(:id).last.is_private?,
           'a user without the manage permission must not create a public board'
  end

  def test_editing_another_users_private_board_is_denied
    other = ExpertAgileQuery.create!(:name => 'Theirs', :project => @project,
                                     :user => User.find(3),
                                     :visibility => Query::VISIBILITY_PRIVATE)

    get :edit, :params => { :id => other.id }

    assert_response :forbidden
  end
end
