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
                          :manage_expert_agile_sprints)
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
  # leak. The check that matters is the private case below.
  def test_agile_data_visibility_follows_the_issue
    get "/issues/#{@issue.id}/expert_agile_data.json"

    assert_response :success, 'project 1 is public in the fixtures'
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

  def test_delete_sprint
    sprint = sprint!

    assert_difference 'ExpertAgileSprint.count', -1 do
      delete "/projects/#{@project.id}/expert_agile_sprints/#{sprint.id}.json", :headers => auth
    end

    assert_response :no_content
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
