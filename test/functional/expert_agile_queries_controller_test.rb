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

  # The complaint that prompted this: the edit form could only rename a saved
  # board, because its configuration was written out as hidden fields taken from
  # the stored record. Filters and options now come from the same panel the
  # board uses, so a saved board can actually be reconfigured.
  def test_edit_renders_the_options_panel
    post :create, :params => board_params
    query = ExpertAgileQuery.order(:id).last

    get :edit, :params => { :id => query.id }

    assert_response :success
    assert_select 'fieldset#filters'
    assert_select 'fieldset#options'
    assert_select 'input[name=?][value=?]', 'board_status_ids[]', @status_id.to_s
  end

  # Edit is reached by submitting the board's own form, so whatever the user has
  # applied in the panel travels with it. Before, the link dropped every unsaved
  # tweak and saving wrote the stored configuration straight back.
  def test_edit_applies_the_configuration_carried_from_the_board
    post :create, :params => board_params
    query = ExpertAgileQuery.order(:id).last

    get :edit, :params => { :id => query.id, :set_filter => '1',
                            :color_base => 'tracker',
                            :board_status_ids => [@status_id.to_s],
                            :wip_limits => { @status_id.to_s => ['1', '3'] } }

    assert_response :success
    assert_select 'select#color_base option[value=?][selected=selected]', 'tracker'
    assert_select 'input[name=?][value=?]', "wip_limits[#{@status_id}][]", '1'
    assert_select 'input[name=?][value=?]', "wip_limits[#{@status_id}][]", '3'
    # Nothing is written until the form is submitted.
    assert_equal 'priority', ExpertAgileQuery.find(query.id).color_base
  end

  def test_edit_without_a_request_configuration_shows_the_stored_one
    post :create, :params => board_params
    query = ExpertAgileQuery.order(:id).last

    get :edit, :params => { :id => query.id }

    assert_select 'select#color_base option[value=?][selected=selected]', 'priority'
    assert_select 'input[name=?][value=?]', "wip_limits[#{@status_id}][]", '2'
    assert_select 'input[name=?][value=?]', "wip_limits[#{@status_id}][]", '5'
  end

  def test_update_changes_the_filters
    post :create, :params => board_params
    query = ExpertAgileQuery.order(:id).last

    put :update, :params => { :id => query.id,
                              :query => { :name => 'My board' },
                              :f => ['status_id'],
                              :op => { 'status_id' => 'o' },
                              :c => %w(status priority) }

    reloaded = ExpertAgileQuery.find(query.id)
    assert_equal ['status_id'], reloaded.filters.keys
    assert_equal 'o', reloaded.filters['status_id'][:operator]
  end

  def test_editing_another_users_private_board_is_denied
    other = ExpertAgileQuery.create!(:name => 'Theirs', :project => @project,
                                     :user => User.find(3),
                                     :visibility => Query::VISIBILITY_PRIVATE)

    get :edit, :params => { :id => other.id }

    assert_response :forbidden
  end
end
