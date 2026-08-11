require File.expand_path('../../test_helper', __FILE__)

class ExpertAgileBacklogsControllerTest < Redmine::ControllerTest
  tests ExpertAgileBacklogsController
  include Redmine::I18n

  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :enabled_modules, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :issues, :issue_categories, :versions, :workflows, :queries

  def setup
    @project = Project.find(1)
    @project.enable_module!(:expert_agile)
    @project.enable_module!(:expert_agile_backlog)
    @role = Role.find(1)
    @role.add_permission!(:view_expert_agile_board, :view_expert_agile_backlog,
                          :manage_expert_agile_backlog, :manage_expert_agile_sprints)
    @request.session[:user_id] = 2
    @issue = Issue.find(1)
  end

  def teardown
    ExpertAgileData.delete_all
    ExpertAgileSprint.delete_all
  end

  def sprint!(attributes = {})
    ExpertAgileSprint.create!({ :project => @project, :name => 'Sprint A',
                                :start_date => Date.new(2026, 1, 1),
                                :end_date => Date.new(2026, 1, 14) }.merge(attributes))
  end

  # --- Rendering -------------------------------------------------------

  def test_index_renders
    sprint!

    get :index, :params => { :project_id => @project.id }

    assert_response :success
    assert_select 'div#ea-backlog'
    assert_select 'div.ea-backlog-lane', :minimum => 2 # backlog + the sprint
  end

  def test_every_lane_has_exactly_one_drop_zone
    # The drop zone is what the drag & drop script binds to; a lane without one,
    # or with a stray second one, silently cannot be planned into.
    sprint!

    get :index, :params => { :project_id => @project.id }

    assert_response :success
    css_select('div.ea-backlog-lane').each do |lane|
      assert_equal 1, lane.css('.ea-backlog-drop').size,
                   'each lane needs exactly one drop target'
    end
  end

  def test_drop_zones_carry_their_container_id
    sprint = sprint!

    get :index, :params => { :project_id => @project.id }

    assert_response :success
    ids = css_select('.ea-backlog-drop').map { |node| node['data-drop-id'] }
    assert_includes ids, sprint.id.to_s
    assert_includes ids, '', 'the unplanned backlog is the lane with no container'
  end

  def test_backlog_lane_is_marked_as_the_source
    sprint!

    get :index, :params => { :project_id => @project.id }

    assert_response :success
    assert_select 'div.ea-backlog-lane.ea-backlog-source', :count => 1
  end

  def test_sprint_lane_shows_its_dates_and_status
    sprint!(:status => ExpertAgileSprint::STATUS_ACTIVE)

    get :index, :params => { :project_id => @project.id }

    assert_response :success
    assert_select '.ea-backlog-lane-meta .ea-backlog-status',
                  :text => l(:label_expert_agile_sprint_status_active)
    assert_select '.ea-backlog-lane-meta', :text => /2026/
  end

  def test_lane_totals
    sprint = sprint!
    issue = Issue.generate!(:project_id => @project.id)
    ExpertAgileData.create!(:issue_id => issue.id, :sprint_id => sprint.id, :story_points => 8)

    get :index, :params => { :project_id => @project.id }

    assert_response :success
    assert_select '.ea-backlog-lane-totals .ea-lane-points', :text => '8'
  end

  def test_empty_lane_explains_itself
    sprint!

    get :index, :params => { :project_id => @project.id }

    assert_response :success
    assert_select '.ea-backlog-empty-hint', :minimum => 1
  end

  def test_switch_marks_the_current_container_type
    get :index, :params => { :project_id => @project.id, :container_type => 'version' }

    assert_response :success
    assert_select '.ea-backlog-switch a.selected', :count => 1
  end

  def test_version_lanes_are_offered
    get :index, :params => { :project_id => @project.id, :container_type => 'version' }

    assert_response :success
    assert_select 'div#ea-backlog'
  end

  def test_index_requires_the_module
    @project.disable_module!(:expert_agile_backlog)

    get :index, :params => { :project_id => @project.id }

    assert_response :forbidden
  end

  def test_index_requires_the_permission
    @role.remove_permission!(:view_expert_agile_backlog)

    get :index, :params => { :project_id => @project.id }

    assert_response :forbidden
  end

  # --- Planning --------------------------------------------------------

  def test_update_plans_an_issue_into_a_sprint
    sprint = sprint!

    put :update, :params => { :project_id => @project.id, :id => @issue.id,
                              :container_id => sprint.id }, :format => :js

    assert_response :success
    assert_equal sprint.id, @issue.reload.expert_agile_data.sprint_id
  end

  def test_update_moves_an_issue_back_to_the_backlog
    sprint = sprint!
    ExpertAgileData.create!(:issue_id => @issue.id, :sprint_id => sprint.id)

    put :update, :params => { :project_id => @project.id, :id => @issue.id,
                              :container_id => '' }, :format => :js

    assert_response :success
    assert_nil @issue.reload.expert_agile_data.sprint_id
  end

  def test_update_rejects_a_container_from_another_project
    foreign = ExpertAgileSprint.create!(:project => Project.find(2), :name => 'Foreign',
                                        :start_date => Date.new(2026, 3, 1),
                                        :end_date => Date.new(2026, 3, 14))

    put :update, :params => { :project_id => @project.id, :id => @issue.id,
                              :container_id => foreign.id }, :format => :js

    assert_response :unprocessable_entity
    assert_nil ExpertAgileData.find_by(:issue_id => @issue.id)&.sprint_id
  end
end
