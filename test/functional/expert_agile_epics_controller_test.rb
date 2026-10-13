require File.expand_path('../../test_helper', __FILE__)

# The epic overview: each epic with everything below it, in tree order.
class ExpertAgileEpicsControllerTest < Redmine::ControllerTest
  tests ExpertAgileEpicsController
  include Redmine::I18n

  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :enabled_modules, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :issues, :issue_categories, :versions, :workflows

  def setup
    @project = Project.find(1)
    @project.enable_module!(:expert_agile)
    @role = Role.find(1)
    @role.add_permission!(:view_expert_agile_board)
    @request.session[:user_id] = 2
    @epic = Issue.generate!(:project => @project, :tracker_id => 2, :subject => 'Checkout')
    @story = Issue.generate!(:project => @project, :tracker_id => 1, :parent_issue_id => @epic.id,
                             :subject => 'Pay by card')
    @subtask = Issue.generate!(:project => @project, :tracker_id => 1, :parent_issue_id => @story.id,
                               :subject => 'Card form')
  end

  def teardown
    ExpertAgileData.delete_all
  end

  def get_epics(params = {})
    with_agile_settings('epic_tracker_ids' => ['2']) do
      get :index, :params => { :project_id => @project.id }.merge(params)
    end
  end

  def test_lists_each_epic_with_its_stories_and_their_subtasks_indented
    get_epics

    assert_response :success
    assert_select 'details.ea-epic-block .ea-epic-title a[href=?]', "/issues/#{@epic.id}"
    assert_select 'tr.ea-epic-row.ea-depth-0 td.subject', :text => /Pay by card/
    assert_select 'tr.ea-epic-row.ea-depth-1 td.subject', :text => /Card form/
    assert_select 'tr.ea-epic-row.ea-depth-0 td.ea-row-subtasks',
                  :text => l(:label_expert_agile_subtasks_done, :closed => 0, :total => 1)
    assert_select '.ea-epic-summary .ea-epic-progress'
  end

  def test_closed_epics_are_folded_away_until_asked_for
    @epic.update_column(:status_id, IssueStatus.where(:is_closed => true).first.id)

    get_epics
    assert_select '.ea-epic-title a[href=?]', "/issues/#{@epic.id}", false
    assert_select '.contextual a', :text => /\(\d+\)/

    get_epics(:closed => '1')
    assert_select '.ea-epic-title a[href=?]', "/issues/#{@epic.id}"
  end

  def test_a_subtask_the_user_cannot_see_is_left_out
    @subtask.update_column(:is_private, true)
    # User 3 is a developer in the project: sees every issue but private ones.
    Role.find(2).add_permission!(:view_expert_agile_board)
    @request.session[:user_id] = 3

    get_epics

    assert_response :success
    assert_select 'td.subject', :text => /Card form/, :count => 0
  end

  def test_the_page_is_gone_while_epics_are_off
    with_agile_settings('epic_tracker_ids' => '') do
      get :index, :params => { :project_id => @project.id }
    end

    assert_response :not_found
  end

  def test_the_page_needs_the_board_permission
    @role.remove_permission!(:view_expert_agile_board)

    get_epics

    assert_response :forbidden
  end
end
