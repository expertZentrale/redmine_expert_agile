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

  # --- Filter and options panel ----------------------------------------

  def test_index_renders_the_filter_panel
    get :index, :params => { :project_id => @project.id }

    assert_response :success
    assert_select 'form#ea_query_form'
    assert_select 'div#query_form_with_buttons'
    assert_select 'fieldset#filters'
    assert_select 'fieldset#options'
    assert_select 'input[name=?][value=?]', 'set_filter', '1'
  end

  def test_the_panel_carries_the_container_type
    # The switch is a pair of links outside the form, so without this hidden
    # field applying a filter on a version backlog drops back to sprints.
    get :index, :params => { :project_id => @project.id, :container_type => 'version' }

    assert_response :success
    assert_select 'form#ea_query_form input[type=hidden][name=?][value=?]',
                  'container_type', 'version'
  end

  def test_container_type_survives_an_apply
    get :index, :params => { :project_id => @project.id, :set_filter => '1',
                             :container_type => 'version' }

    assert_response :success
    assert_select '.ea-backlog-switch a.selected', :text => l(:label_version_plural)
  end

  def test_the_switch_still_works_once_a_session_exists
    # The switch is a plain link, so from the second page view onwards it lands
    # on the session-restore path with no set_filter. Reading the container type
    # only where the query is built from params leaves the switch dead in the
    # browser while every first-request test still passes.
    get :index, :params => { :project_id => @project.id }
    assert_response :success

    get :index, :params => { :project_id => @project.id, :container_type => 'version' }

    assert_response :success
    assert_select '.ea-backlog-switch a.selected', :text => l(:label_version_plural)
    assert_select 'form#ea_query_form input[type=hidden][name=?][value=?]',
                  'container_type', 'version'
  end

  def test_a_switched_container_type_sticks
    get :index, :params => { :project_id => @project.id }
    get :index, :params => { :project_id => @project.id, :container_type => 'version' }

    get :index, :params => { :project_id => @project.id }

    assert_response :success
    assert_select '.ea-backlog-switch a.selected', :text => l(:label_version_plural)
  end

  def test_a_filter_narrows_the_backlog
    wanted = Issue.generate!(:project_id => @project.id)
    other = Issue.generate!(:project_id => @project.id)

    get :index, :params => { :project_id => @project.id, :set_filter => '1',
                             :f => ['issue_id'], :op => { 'issue_id' => '=' },
                             :v => { 'issue_id' => [wanted.id.to_s] } }

    assert_response :success
    assert_select "#ea-card-#{wanted.id}"
    assert_select "#ea-card-#{other.id}", :count => 0
  end

  def test_filters_survive_a_bare_request_through_the_session
    # Coming back via the project menu carries no params at all. Without the
    # session step everything applied from the panel would be lost there.
    wanted = Issue.generate!(:project_id => @project.id)
    other = Issue.generate!(:project_id => @project.id)

    get :index, :params => { :project_id => @project.id, :set_filter => '1',
                             :f => ['issue_id'], :op => { 'issue_id' => '=' },
                             :v => { 'issue_id' => [wanted.id.to_s] } }
    assert_response :success

    get :index, :params => { :project_id => @project.id }

    assert_response :success
    assert_select "#ea-card-#{wanted.id}"
    assert_select "#ea-card-#{other.id}", :count => 0
  end

  def test_card_fields_reach_the_cards
    issue = Issue.generate!(:project_id => @project.id)

    get :index, :params => { :project_id => @project.id, :set_filter => '1',
                             :c => ['priority'] }

    assert_response :success
    assert_select "#ea-card-#{issue.id} .ea-card-fields dt", :text => l(:field_priority)
  end

  def test_the_save_control_needs_the_permission
    get :index, :params => { :project_id => @project.id }
    assert_response :success
    assert_select 'p.buttons .icon-save', :count => 0

    @role.add_permission!(:add_expert_agile_queries)
    get :index, :params => { :project_id => @project.id }

    assert_response :success
    assert_select 'p.buttons input.icon-save[formaction=?]',
                  new_project_expert_agile_backlog_query_path(@project)
  end

  def test_the_buttons_carry_no_inline_event_handlers
    # The planner must work under `script-src 'self'`. Core's filters partial
    # emits inline script and the fieldset legends use core's own
    # toggleFieldset onclick — those are core's markup and the accepted
    # exception. The buttons are ours, so they carry no handler at all.
    @role.add_permission!(:add_expert_agile_queries)

    get :index, :params => { :project_id => @project.id }

    assert_response :success
    assert_select 'p.buttons [onclick]', :count => 0
    assert_select '#ea-backlog [onclick]', :count => 0
    assert_select '#ea-backlog script', :count => 0
  end

  # --- Saved backlogs ---------------------------------------------------

  def saved_backlog!(attributes = {})
    query = ExpertAgileBacklogQuery.new({ :name => 'Version planning', :project => @project,
                                          :user => User.find(2),
                                          :visibility => Query::VISIBILITY_PRIVATE }
                                          .merge(attributes))
    query.container_type = attributes[:container_type] || 'version'
    query.save!
    query
  end

  def test_a_saved_backlog_is_loaded_by_id
    saved = saved_backlog!

    get :index, :params => { :project_id => @project.id, :query_id => saved.id }

    assert_response :success
    assert_select 'h2', :text => 'Version planning'
    assert_select '.ea-backlog-switch a.selected', :text => l(:label_version_plural)
  end

  def test_the_switch_still_works_on_a_saved_backlog
    # The switch link arrives without set_filter, so the container type has to be
    # honoured on the query_id path too or the switch is dead there.
    saved = saved_backlog!

    get :index, :params => { :project_id => @project.id, :query_id => saved.id,
                             :container_type => 'sprint' }

    assert_response :success
    assert_select '.ea-backlog-switch a.selected', :text => l(:label_expert_agile_sprint_plural)
    assert_equal 'version', saved.reload.container_type, 'the tweak is not written back'
  end

  def test_another_users_private_backlog_is_not_reachable_by_id
    # The id is otherwise the only thing protecting somebody else's saved filter
    # set from any member of the same project.
    private_to_someone_else = ExpertAgileBacklogQuery.new(:name => 'Not yours',
                                                          :project => @project,
                                                          :user => User.find(3),
                                                          :visibility => Query::VISIBILITY_PRIVATE)
    private_to_someone_else.save!

    assert_raise ActiveRecord::RecordNotFound do
      get :index, :params => { :project_id => @project.id,
                               :query_id => private_to_someone_else.id }
    end
  end

  def test_a_public_backlog_is_reachable_by_id
    shared = saved_backlog!(:name => 'Team planning', :user => User.find(3),
                            :visibility => Query::VISIBILITY_PUBLIC)

    get :index, :params => { :project_id => @project.id, :query_id => shared.id }

    assert_response :success
    assert_select 'h2', :text => 'Team planning'
  end

  def test_a_saved_backlog_of_another_project_is_not_loaded
    foreign = ExpertAgileBacklogQuery.new(:name => 'Elsewhere', :project => Project.find(2),
                                          :user => User.find(2),
                                          :visibility => Query::VISIBILITY_PRIVATE)
    foreign.save!

    assert_raise ActiveRecord::RecordNotFound do
      get :index, :params => { :project_id => @project.id, :query_id => foreign.id }
    end
  end

  def test_the_sidebar_lists_saved_backlogs
    saved_backlog!

    get :index, :params => { :project_id => @project.id }

    assert_response :success
    assert_select '#sidebar a', :text => 'Version planning'
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
