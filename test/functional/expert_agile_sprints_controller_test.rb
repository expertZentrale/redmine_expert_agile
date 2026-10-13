require File.expand_path('../../test_helper', __FILE__)

# The "Complete sprint" page: the form, the completion, and its refusals.
class ExpertAgileSprintsControllerTest < Redmine::ControllerTest
  tests ExpertAgileSprintsController
  include Redmine::I18n

  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :enabled_modules, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :issues, :workflows

  def setup
    @project = Project.find(1)
    @project.enable_module!(:expert_agile)
    @project.enable_module!(:expert_agile_backlog)
    @role = Role.find(1)
    @role.add_permission!(:view_expert_agile_board, :manage_expert_agile_sprints,
                          :manage_expert_agile_backlog, :view_expert_agile_backlog)
    @request.session[:user_id] = 2
    @sprint = ExpertAgileSprint.create!(:project => @project, :name => 'Sprint 4', :status => ExpertAgileSprint::STATUS_ACTIVE,
                                        :start_date => Date.new(2026, 1, 1), :end_date => Date.new(2026, 1, 14))
    @next = ExpertAgileSprint.create!(:project => @project, :name => 'Sprint 5',
                                      :start_date => Date.new(2026, 1, 15), :end_date => Date.new(2026, 1, 28))
    @open = Issue.generate!(:project => @project)
    @open.expert_agile_data!.update!(:sprint_id => @sprint.id)
  end

  def teardown
    ExpertAgileData.delete_all
    ExpertAgileSprint.delete_all
  end

  def test_the_form_offers_the_next_sprint_the_backlog_and_a_new_one
    get :complete, :params => { :project_id => @project.id, :id => @sprint.id }

    assert_response :success
    assert_select 'input[type=radio][name=target][value=next][checked]'
    assert_select 'input[type=radio][name=target][value=backlog]'
    assert_select 'input[type=radio][name=target][value=new]'
    assert_select 'input[name=?][value=?]', 'new_sprint[name]', 'Sprint 6'
    assert_select '.ea-sprint-complete-issues a[href=?]', "/issues/#{@open.id}"
  end

  def test_completing_moves_closes_and_activates
    post :complete, :params => { :project_id => @project.id, :id => @sprint.id,
                                 :target => 'next', :activate_target => '1' }

    assert_redirected_to project_expert_agile_sprints_path(@project)
    assert_equal @next.id, @open.reload.expert_agile_data.sprint_id
    assert @sprint.reload.closed?
    assert @next.reload.active?
    assert_match 'Sprint 4', flash[:notice]
  end

  def test_a_refusal_rerenders_the_form_with_the_reasons_and_writes_nothing
    @role.remove_permission!(:manage_expert_agile_backlog)

    post :complete, :params => { :project_id => @project.id, :id => @sprint.id, :target => 'next' }

    assert_response :unprocessable_entity
    assert_select '#errorExplanation li a[href=?]', "/issues/#{@open.id}"
    assert @sprint.reload.active?
    assert_equal @sprint.id, @open.reload.expert_agile_data.sprint_id
  end

  def test_a_closed_sprint_cannot_be_completed_again
    @open.expert_agile_data.update!(:sprint_id => nil)
    @sprint.update!(:status => ExpertAgileSprint::STATUS_CLOSED)

    get :complete, :params => { :project_id => @project.id, :id => @sprint.id }

    assert_redirected_to project_expert_agile_sprints_path(@project)
    assert_equal l(:error_expert_agile_sprint_already_closed), flash[:error]
  end

  def test_completing_needs_the_sprint_permission
    @role.remove_permission!(:manage_expert_agile_sprints)

    post :complete, :params => { :project_id => @project.id, :id => @sprint.id, :target => 'backlog' }

    assert_response :forbidden
    assert @sprint.reload.active?
  end

  def test_the_sprint_list_offers_completing_open_sprints_only
    closed = ExpertAgileSprint.create!(:project => @project, :name => 'Sprint 3', :status => ExpertAgileSprint::STATUS_CLOSED,
                                       :start_date => Date.new(2025, 12, 1), :end_date => Date.new(2025, 12, 14))

    get :index, :params => { :project_id => @project.id }

    assert_response :success
    assert_select 'a[href=?]', complete_project_expert_agile_sprint_path(@project, @sprint)
    assert_select 'a[href=?]', complete_project_expert_agile_sprint_path(@project, closed), false
  end

  def test_back_url_returns_to_the_planner
    post :complete, :params => { :project_id => @project.id, :id => @sprint.id, :target => 'backlog',
                                 :back_url => "/projects/#{@project.identifier}/expert_agile/backlog" }

    assert_redirected_to "/projects/#{@project.identifier}/expert_agile/backlog"
  end
end
