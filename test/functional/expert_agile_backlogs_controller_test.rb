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
    # One container kind and one layout are marked, each in its own switch.
    assert_select '.ea-backlog-container-switch a.selected', :count => 1
    assert_select '.ea-backlog-layout-switch a.selected', :count => 1
  end

  def test_version_lanes_are_offered
    get :index, :params => { :project_id => @project.id, :container_type => 'version' }

    assert_response :success
    assert_select 'div#ea-backlog'
  end

  # --- Planning into epics ---------------------------------------------

  def epics!
    epic_a = Issue.generate!(:project => @project, :tracker_id => 2, :subject => 'Epic A')
    epic_b = Issue.generate!(:project => @project, :tracker_id => 2, :subject => 'Epic B')
    story = Issue.generate!(:project => @project, :tracker_id => 1, :parent_issue_id => epic_a.id,
                            :subject => 'Story in A')
    [epic_a, epic_b, story]
  end

  def test_epic_lanes_are_offered_only_while_epics_are_on
    epic_a, epic_b, story = epics!
    subtask = Issue.generate!(:project => @project, :tracker_id => 1, :parent_issue_id => story.id)

    with_agile_settings('epic_tracker_ids' => ['2']) do
      get :index, :params => { :project_id => @project.id, :container_type => 'epic' }
    end

    assert_response :success
    assert_select '.ea-backlog-switch a.selected', :text => l(:label_expert_agile_epic_plural)
    assert_select ".ea-backlog-lane-header[data-container-id=?]", epic_a.id.to_s
    assert_select ".ea-backlog-lane-header[data-container-id=?] .ea-epic-progress", epic_b.id.to_s
    assert_select ".ea-backlog-drop[data-drop-id=?] #ea-card-#{story.id}", epic_a.id.to_s
    assert_select "#ea-card-#{subtask.id}", false, 'a subtask follows its story'
    assert_select "#ea-card-#{epic_a.id}", false, 'the epics are the lanes'

    with_agile_settings('epic_tracker_ids' => '') do
      get :index, :params => { :project_id => @project.id, :container_type => 'epic' }
    end
    assert_select '.ea-backlog-switch a', :text => l(:label_expert_agile_epic_plural), :count => 0
  end

  def test_planning_into_an_epic_makes_the_story_its_subtask
    epic_a, epic_b, story = epics!

    with_agile_settings('epic_tracker_ids' => ['2']) do
      put :update, :params => { :project_id => @project.id, :id => story.id,
                                :container_type => 'epic', :container_id => epic_b.id }, :format => :js
    end

    assert_response :success
    assert_equal epic_b.id, story.reload.parent_id
    # Both epics' bars are refreshed: the one the story left and the one it joined.
    progress = JSON.parse(response.body)['progress']
    assert_empty [epic_a.id, epic_b.id].map(&:to_s) - progress.keys
    assert_equal 0, progress[epic_b.id.to_s]['percent']
    # Counted where it landed, although the planner loaded the epic before
    # the move renumbered the tree.
    assert_equal l(:label_expert_agile_epic_progress_issues, :closed => 0, :total => 1),
                 progress[epic_b.id.to_s]['title']
    assert_equal l(:label_expert_agile_epic_progress_issues, :closed => 0, :total => 0),
                 progress[epic_a.id.to_s]['title']
  end

  # A card moving between two lanes leaves the one it came from with one
  # card fewer; the answer has to say so, or that lane keeps its old count.
  def test_the_lane_a_card_leaves_gets_its_totals
    epic_a, epic_b, story = epics!

    with_agile_settings('epic_tracker_ids' => ['2']) do
      put :update, :params => { :project_id => @project.id, :id => story.id,
                                :container_type => 'epic', :container_id => epic_b.id }, :format => :js
    end

    source = JSON.parse(response.body)['totals']['source']
    assert_equal epic_a.id, source['id']
    assert_equal 0, source['issue_count']
  end

  def test_the_sprint_a_card_leaves_gets_its_totals
    sprint_a = sprint!
    sprint_b = sprint!(:name => 'Sprint B', :start_date => Date.new(2026, 1, 15), :end_date => Date.new(2026, 1, 28))
    @issue.expert_agile_data!.update!(:sprint_id => sprint_a.id)

    put :update, :params => { :project_id => @project.id, :id => @issue.id,
                              :container_type => 'sprint', :container_id => sprint_b.id }, :format => :js

    assert_response :success
    assert_equal sprint_a.id, JSON.parse(response.body)['totals']['source']['id']
  end

  def test_planning_into_the_backlog_takes_the_story_out_of_its_epic
    _epic_a, _epic_b, story = epics!

    with_agile_settings('epic_tracker_ids' => ['2']) do
      put :update, :params => { :project_id => @project.id, :id => story.id,
                                :container_type => 'epic', :container_id => '' }, :format => :js
    end

    assert_response :success
    assert_nil story.reload.parent_id
  end

  def test_planning_a_story_subtask_into_an_epic_is_refused
    _epic_a, epic_b, story = epics!
    subtask = Issue.generate!(:project => @project, :tracker_id => 1, :parent_issue_id => story.id)

    with_agile_settings('epic_tracker_ids' => ['2']) do
      put :update, :params => { :project_id => @project.id, :id => subtask.id,
                                :container_type => 'epic', :container_id => epic_b.id }, :format => :js
    end

    assert_response :unprocessable_entity
    assert_equal story.id, subtask.reload.parent_id
  end

  def test_planning_into_an_epic_needs_the_right_to_manage_subtasks
    _epic_a, epic_b, story = epics!
    @role.remove_permission!(:manage_subtasks)

    with_agile_settings('epic_tracker_ids' => ['2']) do
      put :update, :params => { :project_id => @project.id, :id => story.id,
                                :container_type => 'epic', :container_id => epic_b.id }, :format => :js
    end

    assert_response :forbidden
    assert_equal l(:error_expert_agile_epic_not_editable), JSON.parse(response.body)['error']
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

  def test_a_backlog_that_turns_private_is_dropped_from_the_session
    # The session holds only an id, and it outlives the query it points at.
    # Restoring by id alone means the owner making a shared backlog private has
    # no effect until the viewer's session happens to end.
    shared = saved_backlog!(:name => 'Was shared', :user => User.find(3),
                            :visibility => Query::VISIBILITY_PUBLIC)

    get :index, :params => { :project_id => @project.id, :query_id => shared.id }
    assert_response :success
    assert_select 'h2', :text => 'Was shared'

    shared.update!(:visibility => Query::VISIBILITY_PRIVATE)

    # Same session, no params — the restore path.
    get :index, :params => { :project_id => @project.id }

    assert_response :success
    assert_select 'h2', { :text => 'Was shared', :count => 0 },
                  'a backlog the user may no longer open must not come back from the session'
    assert_select 'h2', :text => l(:label_expert_agile_backlog)
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

  # See the board's copy: Redmine's own refusal carries no body for a .js
  # request, and the planner reads every answer as JSON.
  def test_a_planning_move_refused_for_lack_of_permission_says_so
    sprint = sprint!
    @role.remove_permission!(:manage_expert_agile_backlog)

    put :update, :params => { :project_id => @project.id, :id => @issue.id,
                              :container_id => sprint.id }, :format => :js

    assert_response :forbidden
    assert response.body.present?, 'a refusal the planner cannot read tells the user nothing'
    assert JSON.parse(response.body)['error'].present?
  end

  # A saved backlog can be deleted while the page naming it is still open. The
  # move goes ahead on a fresh query — but which containers are being planned
  # into travels with the request, and a fresh query defaults to sprints, so a
  # move made on the version planner has to keep looking among versions.
  def test_a_move_survives_a_saved_backlog_that_has_been_deleted
    version = Version.generate!(:project => @project)
    saved = ExpertAgileBacklogQuery.create!(:name => 'Gone', :project => @project,
                                            :user => User.find(2),
                                            :visibility => Query::VISIBILITY_PRIVATE)
    id = saved.id
    saved.destroy

    put :update, :params => { :project_id => @project.id, :id => @issue.id,
                              :query_id => id, :container_type => 'version',
                              :container_id => version.id }, :format => :js

    assert_response :success
    assert_equal version.id, @issue.reload.fixed_version_id
  end

  # Only the move speaks the board's JSON dialect. These share the controller
  # and can be asked for as js, so they must keep answering the way they did.
  def test_a_refusal_outside_a_move_is_left_to_redmine
    @role.remove_permission!(:view_expert_agile_backlog, :manage_expert_agile_backlog)

    get :autocomplete, :params => { :project_id => @project.id, :q => 'x' }, :format => :js

    assert_response :forbidden
    assert response.body.blank?,
           'only a card move may be answered in the card move shape'
  end

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

  # --- Who may plan which issue ------------------------------------------

  # The permission used to be checked on the project in the URL only, while the
  # issue could be any visible one. Planning permission in one project was then
  # enough to take issues of every other project out of their sprints.
  def test_update_refuses_an_issue_of_a_project_without_the_planning_permission
    other = Issue.find(4) # project 2, visible to user 2, no backlog module
    their_sprint = sprint!(:project => other.project, :name => 'Their sprint')
    ExpertAgileData.create!(:issue_id => other.id, :sprint_id => their_sprint.id)

    put :update, :params => { :project_id => @project.id, :id => other.id,
                              :container_id => '' }, :format => :js

    assert_response :forbidden
    assert_includes JSON.parse(response.body)['error'], other.project.name
    assert_equal their_sprint.id, other.reload.expert_agile_data.sprint_id
  end

  # `editable?` is already true for someone who may only add notes. Planning
  # changes a field, so it needs what the issue form needs to change it.
  def test_update_refuses_a_user_who_may_only_add_notes
    sprint = sprint!
    @role.remove_permission!(:edit_issues, :edit_own_issues)
    @role.add_permission!(:add_issue_notes)

    put :update, :params => { :project_id => @project.id, :id => @issue.id,
                              :container_id => sprint.id }, :format => :js

    assert_response :forbidden
    assert_equal l(:error_expert_agile_sprint_not_editable), JSON.parse(response.body)['error']
    assert_nil ExpertAgileData.find_by(:issue_id => @issue.id)&.sprint_id
  end

  def test_update_refuses_a_version_the_user_may_not_change
    version = Version.generate!(:project => @project)
    @role.remove_permission!(:edit_issues, :edit_own_issues)
    @role.add_permission!(:add_issue_notes)

    put :update, :params => { :project_id => @project.id, :id => @issue.id,
                              :container_type => 'version',
                              :container_id => version.id }, :format => :js

    assert_response :forbidden
    assert_equal l(:error_expert_agile_version_not_editable), JSON.parse(response.body)['error']
    assert_not_equal version.id, @issue.reload.fixed_version_id
  end

  # The version comes from the backlog's project, the issue can live in any
  # project the user may plan in. A version the issue's own project cannot use
  # must still be refused: Issue validates fixed_version against its
  # assignable_versions, and the planner must surface that, not bypass it.
  def test_update_refuses_a_version_the_issues_project_cannot_use
    elsewhere = Project.generate!(:is_public => true)
    elsewhere.enable_module!(:expert_agile_backlog)
    Member.create!(:project => elsewhere, :principal => User.find(2), :role_ids => [@role.id])
    stranger = Issue.generate!(:project => elsewhere)
    local_only = Version.generate!(:project => @project, :sharing => 'none')
    assert_not_includes stranger.assignable_versions, local_only

    put :update, :params => { :project_id => @project.id, :id => stranger.id,
                              :container_type => 'version',
                              :container_id => local_only.id }, :format => :js

    assert_response :unprocessable_entity
    assert JSON.parse(response.body)['error'].present?
    assert_nil stranger.reload.fixed_version_id
  end

  # A workflow can make the target version read-only for a role. The issue
  # form honours that, and so must the planner.
  def test_update_honours_a_read_only_target_version
    version = Version.generate!(:project => @project)
    WorkflowPermission.create!(:role_id => @role.id, :tracker_id => @issue.tracker_id,
                               :old_status_id => @issue.status_id,
                               :field_name => 'fixed_version_id', :rule => 'readonly')

    put :update, :params => { :project_id => @project.id, :id => @issue.id,
                              :container_type => 'version',
                              :container_id => version.id }, :format => :js

    assert_response :forbidden
    assert_not_equal version.id, @issue.reload.fixed_version_id
  end

  # --- Epic panel ----------------------------------------------------------

  def with_epics(&block)
    with_agile_settings('epic_tracker_ids' => ['2'], &block)
  end

  def panel_link_params(selector)
    Rack::Utils.parse_nested_query(URI(css_select(selector).first['href']).query)
  end

  def test_the_sprint_planner_shows_the_open_epics_in_its_panel
    epic_a, epic_b, _story = epics!
    closed_epic = Issue.generate!(:project => @project, :tracker_id => 2, :status_id => 5)

    with_epics { get :index, :params => { :project_id => @project.id, :container_type => 'sprint' } }

    assert_response :success
    assert_select '#ea-epic-panel .ea-epic-panel-all[aria-current=true]'
    assert_select '#ea-epic-panel .ea-epic-panel-none[data-epic-drop=""]'
    assert_select '#ea-epic-panel .ea-epic-panel-epic[data-epic-drop=?] .ea-epic-progress', epic_a.id.to_s
    assert_select '#ea-epic-panel .ea-epic-panel-epic[data-epic-drop=?]', epic_b.id.to_s
    assert_select "#ea-epic-panel [data-epic-drop='#{closed_epic.id}']", 0
    data = JSON.parse(css_select('#ea-board-data').first.text)
    assert_includes data['epicUpdateUrlTemplate'], '/epic'
  end

  def test_no_epic_panel_on_the_epics_tab_or_without_epic_trackers
    epics!

    with_epics { get :index, :params => { :project_id => @project.id, :container_type => 'epic' } }
    assert_select '#ea-epic-panel', 0

    get :index, :params => { :project_id => @project.id, :container_type => 'sprint' }
    assert_select '#ea-epic-panel', 0
    assert_nil JSON.parse(css_select('#ea-board-data').first.text)['epicUpdateUrlTemplate']
  end

  def test_an_epic_entry_filters_the_planner_to_its_epic
    epic_a, _epic_b, story = epics!
    loose = Issue.generate!(:project => @project, :tracker_id => 1, :subject => 'Loose')

    with_epics { get :index, :params => { :project_id => @project.id, :container_type => 'sprint' } }
    params = panel_link_params(".ea-epic-panel-epic[data-epic-drop='#{epic_a.id}']")
    assert_equal '=', params['op']['expert_agile_epic_id']
    assert_equal [epic_a.id.to_s], params['v']['expert_agile_epic_id']
    assert_equal 'sprint', params['container_type']

    with_epics { get :index, :params => params.merge('project_id' => @project.id) }

    assert_response :success
    assert_select "#ea-card-#{story.id}"
    assert_select "#ea-card-#{loose.id}", 0
    assert_select ".ea-epic-panel-epic[data-epic-drop='#{epic_a.id}'][aria-current=true]"
    # The chosen entry leads back to every issue.
    back = panel_link_params(".ea-epic-panel-epic[data-epic-drop='#{epic_a.id}']")
    assert_nil back.fetch('op', {})['expert_agile_epic_id']
  end

  def test_the_without_epic_entry_keeps_the_other_filters
    epics!

    with_epics do
      get :index, :params => { :project_id => @project.id, :set_filter => '1', :container_type => 'sprint',
                               :f => ['tracker_id'], :op => { 'tracker_id' => '=' }, :v => { 'tracker_id' => ['1'] } }
    end
    params = panel_link_params('.ea-epic-panel-none')

    assert_equal '!*', params['op']['expert_agile_epic_id']
    assert_equal '=', params['op']['tracker_id']
    assert_equal ['1'], params['v']['tracker_id']
  end

  # --- Dropping a card onto an epic ------------------------------------------

  def put_epic(issue, epic_id, extra = {})
    with_epics do
      put :update_epic, :params => { :project_id => @project.id, :id => issue.id, :epic_id => epic_id,
                                     :container_type => 'sprint' }.merge(extra), :format => :js
    end
  end

  def test_a_card_dropped_on_an_epic_becomes_its_story
    epic_a, epic_b, story = epics!

    put_epic(story, epic_b.id)

    assert_response :success
    assert_equal epic_b.id, story.reload.parent_id
    body = JSON.parse(response.body)
    assert_equal true, body['shown']
    assert_equal epic_b.id, body['epicId']
    assert_includes body['card'], "ea-card-#{story.id}"
    assert_equal l(:label_expert_agile_epic_progress_issues, :closed => 0, :total => 1),
                 body['panelProgress'][epic_b.id.to_s]['title']
    assert_equal l(:label_expert_agile_epic_progress_issues, :closed => 0, :total => 0),
                 body['panelProgress'][epic_a.id.to_s]['title']
    assert story.journals.last.details.any? { |detail| detail.prop_key == 'parent_id' }
  end

  def test_a_card_dropped_on_without_epic_leaves_its_epic
    _epic_a, _epic_b, story = epics!

    put_epic(story, '')

    assert_response :success
    assert_nil story.reload.parent_id
  end

  def test_the_card_stays_in_its_sprint_and_its_totals_come_back
    _epic_a, epic_b, story = epics!
    sprint = sprint!
    story.expert_agile_data!.update!(:sprint_id => sprint.id)

    put_epic(story, epic_b.id)

    body = JSON.parse(response.body)
    assert_equal sprint.id, story.reload.expert_agile_data.sprint_id
    assert_equal sprint.id, body['containerId']
    assert_equal 1, body['totals']['container']['issue_count']
  end

  def test_a_card_moved_out_of_the_filtered_epic_leaves_the_screen
    epic_a, epic_b, story = epics!

    put_epic(story, epic_b.id, :set_filter => '1', :f => ['expert_agile_epic_id'],
                               :op => { 'expert_agile_epic_id' => '=' },
                               :v => { 'expert_agile_epic_id' => [epic_a.id.to_s] })

    assert_response :success
    assert_equal false, JSON.parse(response.body)['shown']
  end

  def test_an_epic_outside_the_panel_is_refused
    epic_a, _epic_b, story = epics!
    closed_epic = Issue.generate!(:project => @project, :tracker_id => 2, :status_id => 5)
    foreign = Issue.generate!(:project => Project.find(2), :tracker_id => 2)
    plain = Issue.generate!(:project => @project, :tracker_id => 1)

    [closed_epic, foreign, plain].each do |target|
      put_epic(story, target.id)
      assert_response :unprocessable_entity
      assert_equal l(:error_expert_agile_epic_not_available), JSON.parse(response.body)['error']
    end
    assert_equal epic_a.id, story.reload.parent_id
  end

  def test_a_story_subtask_or_an_epic_is_refused_by_name
    epic_a, epic_b, story = epics!
    subtask = Issue.generate!(:project => @project, :tracker_id => 1, :parent_issue_id => story.id)

    put_epic(subtask, epic_b.id)
    assert_response :unprocessable_entity
    assert_equal l(:error_expert_agile_epic_lane_subtask), JSON.parse(response.body)['error']
    assert_equal story.id, subtask.reload.parent_id

    put_epic(epic_a, epic_b.id)
    assert_response :unprocessable_entity
    assert_equal l(:error_expert_agile_epic_lane_epic), JSON.parse(response.body)['error']
  end

  # Without a panel there is nothing to drop onto, so a crafted request
  # cannot cut a story loose either.
  def test_no_epic_drop_where_the_planner_shows_no_panel
    _epic_a, _epic_b, story = epics!

    with_epics do
      put :update_epic, :params => { :project_id => @project.id, :id => story.id, :epic_id => '',
                                     :container_type => 'epic' }, :format => :js
    end
    assert_response :unprocessable_entity

    put :update_epic, :params => { :project_id => @project.id, :id => story.id, :epic_id => '',
                                   :container_type => 'sprint' }, :format => :js
    assert_response :unprocessable_entity
    assert_not_nil story.reload.parent_id
  end

  # The script sends the planner as it is on screen with every move. A saved
  # planner narrowed to an epic on the panel is that epic, not what it saved.
  def test_the_page_tells_the_script_the_planner_as_it_is_on_screen
    epic_a, _epic_b, _story = epics!
    saved = saved_backlog!(:container_type => 'sprint')

    with_epics do
      get :index, :params => { :project_id => @project.id, :query_id => saved.id, :set_filter => '1',
                               :container_type => 'sprint', :f => ['expert_agile_epic_id', ''],
                               :op => { 'expert_agile_epic_id' => '=' },
                               :v => { 'expert_agile_epic_id' => [epic_a.id.to_s] } }
    end

    state = JSON.parse(css_select('#ea-board-data').first.text)['stateParams']
    assert_equal saved.id, state['query_id']
    assert_equal '1', state['set_filter']
    assert_equal [epic_a.id.to_s], state['v']['expert_agile_epic_id']
  end

  def test_a_move_on_a_tweaked_saved_planner_is_counted_as_on_screen
    epic_a, _epic_b, story = epics!
    loose = Issue.generate!(:project => @project, :tracker_id => 1)
    sprint = sprint!
    loose.expert_agile_data!.update!(:sprint_id => sprint.id)
    saved = saved_backlog!(:container_type => 'sprint')

    with_epics do
      put :update, :params => { :project_id => @project.id, :id => story.id, :container_id => sprint.id,
                                :query_id => saved.id, :set_filter => '1', :container_type => 'sprint',
                                :f => ['expert_agile_epic_id', ''], :op => { 'expert_agile_epic_id' => '=' },
                                :v => { 'expert_agile_epic_id' => [epic_a.id.to_s] } }, :format => :js
    end

    assert_response :success
    # The loose issue in the same sprint is outside the epic on screen.
    assert_equal 1, JSON.parse(response.body)['totals']['container']['issue_count']
  end

  # A saved planner deleted while its page is open: the move still counts
  # what the page was showing, from the state the page sends along.
  def test_a_move_on_a_deleted_saved_planner_keeps_the_filters_on_screen
    epic_a, _epic_b, story = epics!
    loose = Issue.generate!(:project => @project, :tracker_id => 1)
    sprint = sprint!
    loose.expert_agile_data!.update!(:sprint_id => sprint.id)
    saved = saved_backlog!(:container_type => 'sprint')
    id = saved.id
    saved.destroy

    with_epics do
      put :update, :params => { :project_id => @project.id, :id => story.id, :container_id => sprint.id,
                                :query_id => id, :set_filter => '1', :container_type => 'sprint',
                                :f => ['expert_agile_epic_id', ''], :op => { 'expert_agile_epic_id' => '=' },
                                :v => { 'expert_agile_epic_id' => [epic_a.id.to_s] } }, :format => :js
    end

    assert_response :success
    assert_equal 1, JSON.parse(response.body)['totals']['container']['issue_count']
  end

  # Switching tabs or layout on a saved planner narrowed on the panel keeps
  # the epic it was narrowed to.
  def test_the_switches_keep_the_planner_as_it_is_on_screen
    epic_a, _epic_b, _story = epics!
    saved = saved_backlog!(:container_type => 'sprint')

    with_epics do
      get :index, :params => { :project_id => @project.id, :query_id => saved.id, :set_filter => '1',
                               :container_type => 'sprint', :f => ['expert_agile_epic_id', ''],
                               :op => { 'expert_agile_epic_id' => '=' },
                               :v => { 'expert_agile_epic_id' => [epic_a.id.to_s] } }
    end

    [['.ea-backlog-container-switch a', 'container_type', 'version'],
     ['.ea-backlog-layout-switch a', 'planner_layout', 'list']].each do |selector, key, value|
      link = css_select(selector).detect { |a| Rack::Utils.parse_nested_query(URI(a['href']).query)[key] == value }
      params = Rack::Utils.parse_nested_query(URI(link['href']).query)
      assert_equal saved.id.to_s, params['query_id']
      assert_equal [epic_a.id.to_s], params['v']['expert_agile_epic_id'], selector
    end
  end

  def test_dropping_on_an_epic_needs_the_right_to_manage_subtasks
    _epic_a, epic_b, story = epics!
    @role.remove_permission!(:manage_subtasks)

    put_epic(story, epic_b.id)

    assert_response :forbidden
    assert_equal l(:error_expert_agile_epic_not_editable), JSON.parse(response.body)['error']
  end

  def test_dropping_on_an_epic_needs_the_planning_permission
    _epic_a, epic_b, story = epics!
    @role.remove_permission!(:manage_expert_agile_backlog)

    put_epic(story, epic_b.id)

    assert_response :forbidden
    assert_not_equal epic_b.id, story.reload.parent_id
  end

  def test_the_epic_cards_are_hidden_unless_the_options_bring_them_back
    epic_a, _epic_b, story = epics!

    with_epics { get :index, :params => { :project_id => @project.id, :container_type => 'sprint' } }
    assert_select "#ea-card-#{story.id}"
    assert_select "#ea-card-#{epic_a.id}", 0
    assert_select 'input[type=checkbox][name=hide_epics][checked=checked]'
    assert_equal '1', JSON.parse(css_select('#ea-board-data').first.text)['stateParams']['hide_epics']

    with_epics do
      get :index, :params => { :project_id => @project.id, :set_filter => '1', :container_type => 'sprint',
                               :hide_epics => '0' }
    end
    assert_select "#ea-card-#{epic_a.id}"
  end

  # --- Layout ----------------------------------------------------------------

  def test_columns_by_default_with_the_backlog_first
    sprint!

    get :index, :params => { :project_id => @project.id }

    assert_select '#ea-backlog.ea-backlog-list', 0
    assert_select '.ea-backlog-layout-switch a.selected', :text => l(:label_expert_agile_planner_layout_columns)
    assert_includes css_select('#ea-backlog > .ea-backlog-lane').first['class'], 'ea-backlog-source'
  end

  def test_the_setting_can_make_the_list_the_default
    sprint!

    with_agile_settings('planner_default_layout' => 'list') do
      get :index, :params => { :project_id => @project.id }
    end

    assert_select '#ea-backlog.ea-backlog-list'
    assert_select '.ea-backlog-layout-switch a.selected', :text => l(:label_expert_agile_planner_layout_list)
    assert_includes css_select('#ea-backlog > .ea-backlog-lane').last['class'], 'ea-backlog-source'
    assert_select '.ea-backlog-lane[data-lane-key] .ea-lane-toggle', :minimum => 2
  end

  def test_the_layout_switch_sticks_through_the_session
    get :index, :params => { :project_id => @project.id }
    get :index, :params => { :project_id => @project.id, :planner_layout => 'list' }
    assert_select '#ea-backlog.ea-backlog-list'

    get :index, :params => { :project_id => @project.id }

    assert_select '#ea-backlog.ea-backlog-list'
    assert_select 'form#ea_query_form input[type=hidden][name=?][value=?]', 'planner_layout', 'list'
  end

  def test_the_layout_switch_on_a_saved_planner_applies_to_the_request_only
    saved = saved_backlog!

    get :index, :params => { :project_id => @project.id, :query_id => saved.id, :planner_layout => 'list' }

    assert_select '#ea-backlog.ea-backlog-list'
    assert_nil saved.reload.options[:planner_layout], 'the tweak is not written back'
  end

  def test_a_saved_planner_opens_in_its_own_layout
    saved = saved_backlog!
    saved.planner_layout = 'list'
    saved.save!

    get :index, :params => { :project_id => @project.id, :query_id => saved.id }

    assert_select '#ea-backlog.ea-backlog-list'
  end

  # --- Context menu ------------------------------------------------------------

  def test_planner_cards_open_redmines_context_menu
    get :index, :params => { :project_id => @project.id }

    assert_response :success
    assert_select 'form#ea-board-form[data-cm-url=?]', '/issues/context_menu'
    assert_select 'form#ea-board-form input[type=hidden][name=back_url]'
    assert_select "form#ea-board-form #ea-card-#{@issue.id}.hascontextmenu input[type=checkbox][name=?]", 'ids[]'
    assert_select "#ea-card-#{@issue.id} .ea-card-header .js-contextmenu"
  end
end
