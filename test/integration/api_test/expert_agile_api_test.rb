require File.expand_path('../../../test_helper', __FILE__)

# REST API: agile data per issue, and sprint CRUD.
#
# Drives the real stack through Redmine::IntegrationTest with API-key auth,
# including the permission negatives — an endpoint that only ever gets tested
# with a privileged user is not tested.
class ExpertAgileApiTest < Redmine::IntegrationTest
  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :enabled_modules, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :issues, :issue_categories, :versions, :workflows

  def setup
    Setting.rest_api_enabled = '1'
    @project = Project.find(1)
    @project.enable_module!(:expert_agile)
    @project.enable_module!(:expert_agile_backlog)
    @role = Role.find(1)
    @role.add_permission!(:view_expert_agile_board, :edit_expert_agile_board,
                          :manage_expert_agile_sprints, :manage_expert_agile_backlog)
    @user = User.find(2)
    @user.api_key
    @issue = Issue.find(1)
  end

  def teardown
    Setting.rest_api_enabled = '0'
    ExpertAgileData.delete_all
    ExpertAgileSprint.delete_all
  end

  def auth
    { 'X-Redmine-API-Key' => @user.api_key }
  end

  def sprint!(attributes = {})
    ExpertAgileSprint.create!({ :project => @project, :name => 'Sprint A',
                                :start_date => Date.new(2026, 1, 1),
                                :end_date => Date.new(2026, 1, 14) }.merge(attributes))
  end

  # --- Agile data --------------------------------------------------------

  def test_get_agile_data
    ExpertAgileData.create!(:issue_id => @issue.id, :story_points => 5, :position => 100)

    get "/issues/#{@issue.id}/expert_agile_data.json", :headers => auth

    assert_response :success
    body = JSON.parse(response.body)['expert_agile_data']
    assert_equal @issue.id, body['issue_id']
    assert_equal 5, body['story_points']
  end

  def test_get_agile_data_for_an_issue_with_no_row
    get "/issues/#{@issue.id}/expert_agile_data.json", :headers => auth

    assert_response :success
    body = JSON.parse(response.body)['expert_agile_data']
    assert_nil body['story_points']
  end

  # Visibility follows the issue, which is the right model: in a public project
  # anonymous may already read the issue, so reading its agile data is not a
  # leak once the anonymous role may also view the board. The check that
  # matters is the private case below.
  def test_agile_data_visibility_follows_the_issue
    Role.anonymous.add_permission!(:view_expert_agile_board)

    get "/issues/#{@issue.id}/expert_agile_data.json"

    assert_response :success, 'project 1 is public in the fixtures'
  end

  # The agile data of an issue is board data: seeing the issue is not enough
  # when the role may not view the board.
  def test_agile_data_is_not_readable_anonymously_without_the_board_permission
    Role.anonymous.remove_permission!(:view_expert_agile_board)

    get "/issues/#{@issue.id}/expert_agile_data.json"

    assert_includes [401, 403], response.status
  end

  def test_agile_data_is_not_readable_anonymously_in_a_private_project
    @project.update!(:is_public => false)

    get "/issues/#{@issue.id}/expert_agile_data.json"

    assert_not response.successful?, 'a private project must not expose agile data'
    assert_includes [401, 403, 404], response.status
  end

  def test_put_agile_data_sets_story_points
    put "/issues/#{@issue.id}/expert_agile_data.json",
        :params => { :expert_agile_data => { :story_points => 8 } }.to_json,
        :headers => auth.merge('Content-Type' => 'application/json')

    assert_response :no_content
    assert_equal 8, @issue.reload.story_points
  end

  def test_put_agile_data_clears_story_points
    ExpertAgileData.create!(:issue_id => @issue.id, :story_points => 5)

    put "/issues/#{@issue.id}/expert_agile_data.json",
        :params => { :expert_agile_data => { :story_points => '' } }.to_json,
        :headers => auth.merge('Content-Type' => 'application/json')

    assert_response :no_content
    assert_nil @issue.reload.story_points
  end

  def test_put_agile_data_assigns_a_sprint
    sprint = sprint!

    put "/issues/#{@issue.id}/expert_agile_data.json",
        :params => { :expert_agile_data => { :sprint_id => sprint.id } }.to_json,
        :headers => auth.merge('Content-Type' => 'application/json')

    assert_response :no_content
    assert_equal sprint.id, @issue.reload.expert_agile_data.sprint_id
  end

  def test_put_agile_data_rejects_a_sprint_from_another_project
    foreign = ExpertAgileSprint.create!(:project => Project.find(2), :name => 'Foreign',
                                        :start_date => Date.new(2026, 3, 1),
                                        :end_date => Date.new(2026, 3, 14))

    put "/issues/#{@issue.id}/expert_agile_data.json",
        :params => { :expert_agile_data => { :sprint_id => foreign.id } }.to_json,
        :headers => auth.merge('Content-Type' => 'application/json')

    assert_response :unprocessable_entity
    assert_nil ExpertAgileData.find_by(:issue_id => @issue.id)&.sprint_id
  end

  def test_put_agile_data_rejects_invalid_story_points
    put "/issues/#{@issue.id}/expert_agile_data.json",
        :params => { :expert_agile_data => { :story_points => -3 } }.to_json,
        :headers => auth.merge('Content-Type' => 'application/json')

    assert_response :unprocessable_entity
  end

  def test_put_agile_data_denied_without_edit_rights
    @role.remove_permission!(:edit_issues, :add_issue_notes)

    put "/issues/#{@issue.id}/expert_agile_data.json",
        :params => { :expert_agile_data => { :story_points => 8 } }.to_json,
        :headers => auth.merge('Content-Type' => 'application/json')

    assert_response :forbidden
  end

  # `editable?` is true for anyone who may add notes; the issue form needs the
  # edit permission for these fields, and so must the REST endpoint.
  def test_put_agile_data_denied_to_a_user_who_may_only_add_notes
    @role.remove_permission!(:edit_issues, :edit_own_issues)
    @role.add_permission!(:add_issue_notes)
    assert @issue.editable?(@user), 'the setup must leave the issue editable in the loose sense'

    put "/issues/#{@issue.id}/expert_agile_data.json",
        :params => { :expert_agile_data => { :story_points => 8, :sprint_id => sprint!.id } }.to_json,
        :headers => auth.merge('Content-Type' => 'application/json')

    assert_response :forbidden
    assert_nil ExpertAgileData.find_by(:issue_id => @issue.id)
  end

  def test_put_agile_data_needs_the_board_permission
    @role.remove_permission!(:edit_expert_agile_board)

    put "/issues/#{@issue.id}/expert_agile_data.json",
        :params => { :expert_agile_data => { :story_points => 8 } }.to_json,
        :headers => auth.merge('Content-Type' => 'application/json')

    assert_response :forbidden
  end

  def test_put_agile_data_needs_the_agile_module
    @project.disable_module!(:expert_agile)

    put "/issues/#{@issue.id}/expert_agile_data.json",
        :params => { :expert_agile_data => { :story_points => 8 } }.to_json,
        :headers => auth.merge('Content-Type' => 'application/json')

    assert_response :forbidden
  end

  def test_get_agile_data_needs_the_board_permission
    @role.remove_permission!(:view_expert_agile_board)

    get "/issues/#{@issue.id}/expert_agile_data.json", :headers => auth

    assert_response :forbidden
  end

  # A sprint change through the REST endpoint used to be written without a
  # journal, so it left no trace in the issue history.
  def test_put_agile_data_records_the_sprint_change_in_the_history
    sprint = sprint!

    assert_difference 'Journal.count', 1 do
      put "/issues/#{@issue.id}/expert_agile_data.json",
          :params => { :expert_agile_data => { :sprint_id => sprint.id } }.to_json,
          :headers => auth.merge('Content-Type' => 'application/json')
    end

    assert_response :no_content
    detail = JournalDetail.where(:prop_key => 'expert_agile_sprint_id').order(:id).last
    assert_equal sprint.id.to_s, detail.value
    assert_equal @user, detail.journal.user
  end

  # --- Sprints -----------------------------------------------------------

  def test_list_sprints
    sprint!

    get "/projects/#{@project.id}/expert_agile_sprints.json", :headers => auth

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body['expert_agile_sprints'].size
    assert_equal 'Sprint A', body['expert_agile_sprints'].first['name']
  end

  def test_show_sprint
    sprint = sprint!

    get "/projects/#{@project.id}/expert_agile_sprints/#{sprint.id}.json", :headers => auth

    assert_response :success
    body = JSON.parse(response.body)['expert_agile_sprint']
    assert_equal 'Sprint A', body['name']
    assert_equal 'open', body['status']
  end

  # A shared sprint holds issues of other projects. The totals must count only
  # the ones the caller can see, or they report on projects outside their reach.
  def test_show_sprint_counts_only_issues_the_caller_can_see
    sprint = sprint!(:sharing => ExpertAgileSprint::SHARING_SYSTEM)
    elsewhere = Project.generate!(:is_public => false) # user 2 is no member
    hidden = Issue.generate!(:project => elsewhere)
    assert_not hidden.visible?(@user)
    ExpertAgileData.create!(:issue_id => @issue.id, :sprint_id => sprint.id, :story_points => 3)
    ExpertAgileData.create!(:issue_id => hidden.id, :sprint_id => sprint.id, :story_points => 40)

    get "/projects/#{@project.id}/expert_agile_sprints/#{sprint.id}.json", :headers => auth

    assert_response :success
    body = JSON.parse(response.body)['expert_agile_sprint']
    assert_equal 1, body['issue_count']
    assert_equal 3, body['story_points']
  end

  def test_create_sprint
    assert_difference 'ExpertAgileSprint.count', 1 do
      post "/projects/#{@project.id}/expert_agile_sprints.json",
           :params => { :expert_agile_sprint => { :name => 'Sprint B',
                                                  :start_date => '2026-04-01',
                                                  :end_date => '2026-04-14' } }.to_json,
           :headers => auth.merge('Content-Type' => 'application/json')
    end

    assert_response :created
  end

  def test_create_sprint_validation_errors
    assert_no_difference 'ExpertAgileSprint.count' do
      post "/projects/#{@project.id}/expert_agile_sprints.json",
           :params => { :expert_agile_sprint => { :name => '' } }.to_json,
           :headers => auth.merge('Content-Type' => 'application/json')
    end

    assert_response :unprocessable_entity
  end

  def test_update_sprint
    sprint = sprint!

    put "/projects/#{@project.id}/expert_agile_sprints/#{sprint.id}.json",
        :params => { :expert_agile_sprint => { :name => 'Renamed' } }.to_json,
        :headers => auth.merge('Content-Type' => 'application/json')

    assert_response :no_content
    assert_equal 'Renamed', sprint.reload.name
  end

  # --- Who may share a sprint how widely ----------------------------------

  # A system-wide sprint shows its name and dates in every project of the
  # instance. Core keeps that step for administrators on versions, and so
  # does the sprint.
  def test_a_project_member_cannot_share_a_sprint_with_every_project
    assert_no_difference 'ExpertAgileSprint.count' do
      post "/projects/#{@project.id}/expert_agile_sprints.json",
           :params => { :expert_agile_sprint => { :name => 'Everywhere',
                                                  :start_date => '2026-04-01',
                                                  :end_date => '2026-04-14',
                                                  :sharing => ExpertAgileSprint::SHARING_SYSTEM } }.to_json,
           :headers => auth.merge('Content-Type' => 'application/json')
    end

    assert_response :unprocessable_entity
  end

  def test_a_project_member_cannot_widen_an_existing_sprint_to_every_project
    sprint = sprint!

    put "/projects/#{@project.id}/expert_agile_sprints/#{sprint.id}.json",
        :params => { :expert_agile_sprint => { :sharing => ExpertAgileSprint::SHARING_SYSTEM } }.to_json,
        :headers => auth.merge('Content-Type' => 'application/json')

    assert_response :unprocessable_entity
    assert_equal ExpertAgileSprint::SHARING_NONE, sprint.reload.sharing
  end

  def test_an_administrator_can_share_a_sprint_with_every_project
    admin = User.find(1)

    post "/projects/#{@project.id}/expert_agile_sprints.json",
         :params => { :expert_agile_sprint => { :name => 'Everywhere',
                                                :start_date => '2026-04-01',
                                                :end_date => '2026-04-14',
                                                :sharing => ExpertAgileSprint::SHARING_SYSTEM } }.to_json,
         :headers => { 'X-Redmine-API-Key' => admin.api_key, 'Content-Type' => 'application/json' }

    assert_response :created
    assert_equal ExpertAgileSprint::SHARING_SYSTEM, ExpertAgileSprint.find_by(:name => 'Everywhere').sharing
  end

  # Once an administrator has shared a sprint, the project's own sprint
  # managers must still be able to rename or reschedule it.
  def test_a_sprint_shared_by_an_administrator_stays_editable_for_the_project
    sprint = sprint!(:sharing => ExpertAgileSprint::SHARING_SYSTEM)

    put "/projects/#{@project.id}/expert_agile_sprints/#{sprint.id}.json",
        :params => { :expert_agile_sprint => { :name => 'Renamed',
                                               :sharing => ExpertAgileSprint::SHARING_SYSTEM } }.to_json,
        :headers => auth.merge('Content-Type' => 'application/json')

    assert_response :no_content
    assert_equal 'Renamed', sprint.reload.name
  end

  # Sharing with the whole tree reaches sibling projects, so it needs the
  # sprint permission in the root project, as versions need manage_versions.
  def test_sharing_with_the_tree_needs_the_permission_in_the_root_project
    child = Project.find(5) # private subproject of project 1, user 2 is a member
    child.enable_module!(:expert_agile)
    @project.disable_module!(:expert_agile)

    post "/projects/#{child.id}/expert_agile_sprints.json",
         :params => { :expert_agile_sprint => { :name => 'Tree wide',
                                                :start_date => '2026-04-01',
                                                :end_date => '2026-04-14',
                                                :sharing => ExpertAgileSprint::SHARING_TREE } }.to_json,
         :headers => auth.merge('Content-Type' => 'application/json')
    assert_response :unprocessable_entity

    @project.reload.enable_module!(:expert_agile)
    post "/projects/#{child.id}/expert_agile_sprints.json",
         :params => { :expert_agile_sprint => { :name => 'Tree wide',
                                                :start_date => '2026-04-01',
                                                :end_date => '2026-04-14',
                                                :sharing => ExpertAgileSprint::SHARING_TREE } }.to_json,
         :headers => auth.merge('Content-Type' => 'application/json')
    assert_response :created
  end

  def test_the_form_offers_only_the_sharings_the_user_may_set
    log_user('jsmith', 'jsmith')

    get "/projects/#{@project.id}/expert_agile_sprints/new"

    assert_response :success
    select = 'select[name=?] option[value=?]'
    assert_select select, 'expert_agile_sprint[sharing]', ExpertAgileSprint::SHARING_SYSTEM.to_s, false
    assert_select select, 'expert_agile_sprint[sharing]', ExpertAgileSprint::SHARING_DESCENDANTS.to_s
  end

  def test_sharing_with_subprojects_needs_no_further_permission
    post "/projects/#{@project.id}/expert_agile_sprints.json",
         :params => { :expert_agile_sprint => { :name => 'Down the tree',
                                                :start_date => '2026-04-01',
                                                :end_date => '2026-04-14',
                                                :sharing => ExpertAgileSprint::SHARING_DESCENDANTS } }.to_json,
         :headers => auth.merge('Content-Type' => 'application/json')

    assert_response :created
  end

  def test_delete_sprint
    sprint = sprint!

    assert_difference 'ExpertAgileSprint.count', -1 do
      delete "/projects/#{@project.id}/expert_agile_sprints/#{sprint.id}.json", :headers => auth
    end

    assert_response :no_content
  end

  # Deleting a shared sprint used to un-plan the issues of every project it was
  # shared with, silently. Core refuses to delete a version still in use.
  def test_a_sprint_used_by_another_project_is_not_deleted
    sprint = sprint!(:sharing => ExpertAgileSprint::SHARING_SYSTEM)
    elsewhere = Issue.find(4) # project 2
    ExpertAgileData.create!(:issue_id => elsewhere.id, :sprint_id => sprint.id)

    assert_no_difference 'ExpertAgileSprint.count' do
      delete "/projects/#{@project.id}/expert_agile_sprints/#{sprint.id}.json", :headers => auth
    end

    assert_response :unprocessable_entity
    assert_equal sprint.id, elsewhere.reload.expert_agile_data.sprint_id
  end

  def test_a_sprint_used_only_by_its_own_project_is_deleted
    sprint = sprint!
    ExpertAgileData.create!(:issue_id => @issue.id, :sprint_id => sprint.id)

    assert_difference 'ExpertAgileSprint.count', -1 do
      delete "/projects/#{@project.id}/expert_agile_sprints/#{sprint.id}.json", :headers => auth
    end

    assert_response :no_content
    assert_nil @issue.reload.expert_agile_data.sprint_id
  end

  def test_sprints_denied_without_permission
    @role.remove_permission!(:manage_expert_agile_sprints)

    get "/projects/#{@project.id}/expert_agile_sprints.json", :headers => auth

    assert_response :forbidden
  end

  def test_sprints_denied_when_module_disabled
    @project.disable_module!(:expert_agile)

    get "/projects/#{@project.id}/expert_agile_sprints.json", :headers => auth

    assert_response :forbidden
  end

  def test_xml_format_is_supported
    sprint!

    get "/projects/#{@project.id}/expert_agile_sprints.xml", :headers => auth

    assert_response :success
    assert_select 'expert_agile_sprints expert_agile_sprint name', :text => 'Sprint A'
  end
end
