require File.expand_path('../../test_helper', __FILE__)

# The backlog planner query, exercised against both container kinds through the
# same tests — the point of the parameterised design is that sprint and version
# planning behave identically.
class ExpertAgileBacklogQueryTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles,
           :enabled_modules, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :issues, :versions

  def setup
    @project = Project.find(1)
    @project.enable_module!(:expert_agile)
    @project.enable_module!(:expert_agile_backlog)
    User.current = User.find(1)
  end

  def teardown
    User.current = nil
    ExpertAgileData.delete_all
    ExpertAgileSprint.delete_all
  end

  def query_for(container_type)
    query = ExpertAgileBacklogQuery.new(:name => '_', :project => @project)
    query.container_type = container_type
    query
  end

  def make_sprint
    ExpertAgileSprint.create!(:project => @project, :name => 'Sprint A',
                              :start_date => Date.new(2026, 1, 1),
                              :end_date => Date.new(2026, 1, 14))
  end

  def plan_into(query, issue, container)
    if query.sprints?
      data = issue.expert_agile_data || issue.build_expert_agile_data
      data.sprint_id = container.id
      data.save!
    else
      issue.fixed_version_id = container.id
      issue.save!
    end
  end

  # --- Container type ---------------------------------------------------

  def test_container_type_defaults_to_sprint_and_rejects_junk
    query = ExpertAgileBacklogQuery.new(:name => '_', :project => @project)

    assert_equal 'sprint', query.container_type
    assert query.sprints?

    query.container_type = 'nonsense'
    assert_equal 'sprint', query.container_type

    query.container_type = 'version'
    assert_not query.sprints?
  end

  def test_apply_board_params_sets_the_container_type
    query = ExpertAgileBacklogQuery.new(:name => '_', :project => @project)

    query.apply_board_params(:container_type => 'version')
    assert_equal 'version', query.container_type

    query.apply_board_params(:container_type => 'nonsense')
    assert_equal 'sprint', query.container_type, 'junk falls back to the default'
  end

  def test_the_container_type_survives_the_session_round_trip
    # It is display state like every other panel setting, so it has to come back
    # when the user returns to the planner without any params.
    assert_includes ExpertAgileBacklogQuery.session_option_keys, :container_type

    restored = ExpertAgileBacklogQuery.new(:name => '_', :project => @project)
    restored.restore_board_options(query_for('version').board_session_options)

    assert_equal 'version', restored.container_type
  end

  def test_a_board_does_not_carry_the_container_type
    assert_not_includes ExpertAgileQuery.session_option_keys, :container_type
  end

  # --- Saving -----------------------------------------------------------

  def test_a_backlog_can_be_saved_and_reloaded
    query = query_for('version')
    query.name = 'Version planning'
    query.user = User.current
    query.visibility = Query::VISIBILITY_PRIVATE

    assert query.save, query.errors.full_messages.join(', ')

    reloaded = ExpertAgileBacklogQuery.find(query.id)
    assert_equal ExpertAgileBacklogQuery, reloaded.class
    assert_equal 'version', reloaded.container_type
  end

  def test_visibility_is_gated_on_the_backlog_permission
    # It would otherwise inherit the board's, and the two are separate project
    # modules — a project may well have the backlog without the board.
    assert_equal :view_expert_agile_backlog, ExpertAgileBacklogQuery.view_permission
  end

  def test_containers_list_sprints_or_versions
    sprint = make_sprint

    assert_includes query_for('sprint').containers, sprint
    assert_equal @project.shared_versions.open.sorted.to_a, query_for('version').containers
  end

  def test_closed_sprints_are_not_plannable
    sprint = make_sprint
    sprint.update!(:status => ExpertAgileSprint::STATUS_CLOSED)

    assert_not_includes query_for('sprint').containers, sprint
  end

  # --- Planning ---------------------------------------------------------

  def test_planned_and_unplanned_issues_are_separated
    %w(sprint version).each do |kind|
      query = query_for(kind)
      container = kind == 'sprint' ? make_sprint : @project.shared_versions.open.first
      next if container.nil?

      planned = Issue.generate!(:project_id => @project.id)
      unplanned = Issue.generate!(:project_id => @project.id)
      plan_into(query, planned, container)

      assert_includes query.issues_for(container).map(&:id), planned.id, kind
      assert_not_includes query.issues_for(container).map(&:id), unplanned.id, kind
      assert_includes query.backlog_issues.map(&:id), unplanned.id, kind
      assert_not_includes query.backlog_issues.map(&:id), planned.id, kind

      ExpertAgileData.delete_all
      ExpertAgileSprint.delete_all
    end
  end

  def test_totals_count_issues_and_story_points
    query = query_for('sprint')
    sprint = make_sprint
    issue = Issue.generate!(:project_id => @project.id)
    plan_into(query, issue, sprint)
    issue.expert_agile_data.update!(:story_points => 8)

    totals = query.totals_for(sprint)

    assert_equal 1, totals[:issue_count]
    assert_equal 8, totals[:story_points].to_i
  end

  def test_backlog_can_be_searched_by_subject_and_by_id
    query = query_for('sprint')
    issue = Issue.generate!(:project_id => @project.id, :subject => 'Findable widget')

    assert_includes query.backlog_issues('widget').map(&:id), issue.id
    assert_includes query.backlog_issues("##{issue.id}").map(&:id), issue.id
    assert_not_includes query.backlog_issues('nothing matches this').map(&:id), issue.id
  end

  # A search for "%" or "_" used to match every issue: they reached LIKE as
  # wildcards.
  def test_search_wildcards_are_literal_characters
    query = query_for('sprint')
    plain = Issue.generate!(:project_id => @project.id, :subject => 'Plain subject')
    percent = Issue.generate!(:project_id => @project.id, :subject => 'Done 100% of it')

    assert_not_includes query.backlog_issues('%').map(&:id), plain.id
    assert_includes query.backlog_issues('%').map(&:id), percent.id
    assert_not_includes query.backlog_issues('_').map(&:id), plain.id
  end

  # --- Container resolution ---------------------------------------------

  def test_container_for_resolves_only_available_containers
    query = query_for('sprint')
    sprint = make_sprint

    assert_equal sprint, query.container_for(sprint.id)
    assert_nil query.container_for(nil)
    assert_nil query.container_for('')
  end

  def test_container_for_rejects_a_sprint_of_an_unrelated_project
    # The id arrives from the request. Resolving it against the project's own
    # plannable containers is what stops a crafted id moving an issue into
    # another project's sprint.
    other_project = Project.find(2)
    foreign = ExpertAgileSprint.create!(:project => other_project, :name => 'Foreign',
                                        :start_date => Date.new(2026, 5, 1),
                                        :end_date => Date.new(2026, 5, 14))

    assert_nil query_for('sprint').container_for(foreign.id)
  end

  def test_container_for_accepts_a_shared_sprint_from_another_project
    other_project = Project.find(2)
    shared = ExpertAgileSprint.create!(:project => other_project, :name => 'Shared',
                                       :start_date => Date.new(2026, 6, 1),
                                       :end_date => Date.new(2026, 6, 14),
                                       :sharing => ExpertAgileSprint::SHARING_SYSTEM)

    assert_equal shared, query_for('sprint').container_for(shared.id)
  end

  # --- Ordering ---------------------------------------------------------

  def test_lanes_are_rank_ordered
    query = query_for('sprint')
    sprint = make_sprint
    first = Issue.generate!(:project_id => @project.id)
    second = Issue.generate!(:project_id => @project.id)
    plan_into(query, first, sprint)
    plan_into(query, second, sprint)
    first.expert_agile_data.update!(:position => 200)
    second.expert_agile_data.update!(:position => 100)

    assert_equal [second.id, first.id], query.issues_for(sprint).map(&:id)
  end

  def test_siblings_for_returns_the_lane_being_ranked_within
    query = query_for('sprint')
    sprint = make_sprint
    planned = Issue.generate!(:project_id => @project.id)
    unplanned = Issue.generate!(:project_id => @project.id)
    plan_into(query, planned, sprint)

    assert_includes query.siblings_for(sprint).map(&:id), planned.id
    assert_includes query.siblings_for(nil).map(&:id), unplanned.id
    assert_not_includes query.siblings_for(nil).map(&:id), planned.id
  end

  # --- Layout -----------------------------------------------------------

  def test_a_planner_without_a_layout_follows_the_setting
    query = query_for('sprint')

    assert_equal 'columns', query.planner_layout
    with_agile_settings('planner_default_layout' => 'list') do
      assert_equal 'list', query.planner_layout
      assert query.list_layout?
    end
  end

  def test_a_planner_keeps_a_layout_of_its_own_and_ignores_junk
    query = query_for('sprint')
    query.apply_board_params(:planner_layout => 'list')

    with_agile_settings('planner_default_layout' => 'columns') do
      assert_equal 'list', query.planner_layout
    end
    query.apply_board_params(:planner_layout => 'nonsense')
    assert_equal 'list', query.planner_layout, 'junk leaves the layout as it was'
    assert_equal 'columns', query_for('sprint').tap { |q| q.planner_layout = 'nonsense' }.planner_layout
  end

  def test_junk_in_the_setting_reads_as_columns
    with_agile_settings('planner_default_layout' => 'nonsense') do
      assert_equal 'columns', RedmineExpertAgile.planner_default_layout
      assert_equal 'columns', query_for('sprint').planner_layout
    end
  end

  def test_the_layout_survives_the_session_round_trip_and_a_save
    assert_includes ExpertAgileBacklogQuery.session_option_keys, :planner_layout
    query = query_for('version')
    query.planner_layout = 'list'

    restored = ExpertAgileBacklogQuery.new(:name => '_', :project => @project)
    restored.restore_board_options(query.board_session_options)
    assert_equal 'list', restored.planner_layout

    query.name = 'List planning'
    query.user = User.current
    query.visibility = Query::VISIBILITY_PRIVATE
    assert query.save, query.errors.full_messages.join(', ')
    with_agile_settings('planner_default_layout' => 'columns') do
      assert_equal 'list', ExpertAgileBacklogQuery.find(query.id).planner_layout
    end
  end

  def test_as_columns_the_backlog_leads_as_a_list_it_closes
    sprint = make_sprint
    query = query_for('sprint')

    assert_equal [nil, sprint], query.lanes
    query.planner_layout = 'list'
    assert_equal [sprint, nil], query.lanes
  end

  # --- Epic panel ---------------------------------------------------------

  def with_epics(&block)
    with_agile_settings('epic_tracker_ids' => ['2'], &block)
  end

  def test_the_panel_lists_the_open_epics_by_subject
    zebra = Issue.generate!(:project => @project, :tracker_id => 2, :subject => 'Zebra')
    alpha = Issue.generate!(:project => @project, :tracker_id => 2, :subject => 'Alpha')
    sub = Issue.generate!(:project => Project.find(3), :tracker_id => 2, :subject => 'Middle') # a subproject
    Issue.generate!(:project => @project, :tracker_id => 2, :subject => 'Done', :status_id => 5)
    Issue.generate!(:project => Project.find(2), :tracker_id => 2, :subject => 'Elsewhere')

    with_epics do
      query = query_for('sprint')
      ids = query.panel_epics.map(&:id)
      assert_equal [alpha.id, sub.id, zebra.id], ids & [alpha.id, sub.id, zebra.id]
      assert query.panel_epics.all? { |epic| epic.tracker_id == 2 && !epic.closed? }
      assert query.panel_epics.none? { |epic| epic.project_id == 2 }
      assert query.epic_panel?
      assert_equal query.panel_epics, query.epics_on_screen
    end
  end

  def test_no_panel_on_the_epics_tab_or_without_epic_trackers
    Issue.generate!(:project => @project, :tracker_id => 2)

    with_epics { assert_not query_for('epic').epic_panel? }
    assert_not query_for('sprint').epic_panel?
    assert_empty query_for('sprint').panel_epics
  end

  def test_the_panel_ignores_the_epic_filter_it_sets
    alpha = Issue.generate!(:project => @project, :tracker_id => 2, :subject => 'Alpha')
    beta = Issue.generate!(:project => @project, :tracker_id => 2, :subject => 'Beta')

    with_epics do
      query = query_for('sprint')
      query.add_filter('expert_agile_epic_id', '=', [alpha.id.to_s])
      assert_includes query.panel_epics.map(&:id), beta.id
    end
  end

  def test_panel_epic_for_resolves_only_the_panels_epics
    open_epic = Issue.generate!(:project => @project, :tracker_id => 2)
    closed_epic = Issue.generate!(:project => @project, :tracker_id => 2, :status_id => 5)
    foreign = Issue.generate!(:project => Project.find(2), :tracker_id => 2)
    story = Issue.generate!(:project => @project, :tracker_id => 1)

    with_epics do
      query = query_for('sprint')
      assert_equal open_epic, query.panel_epic_for(open_epic.id.to_s)
      [closed_epic, foreign, story].each { |issue| assert_nil query.panel_epic_for(issue.id) }
      assert_nil query.panel_epic_for('')
    end
  end

  def test_shows_issue_follows_the_filters
    epic = Issue.generate!(:project => @project, :tracker_id => 2)
    story = Issue.generate!(:project => @project, :tracker_id => 1, :parent_issue_id => epic.id)
    loose = Issue.generate!(:project => @project, :tracker_id => 1)

    with_epics do
      query = query_for('sprint')
      query.add_filter('expert_agile_epic_id', '=', [epic.id.to_s])
      assert query.shows_issue?(story.reload)
      assert_not query.shows_issue?(loose)
    end
  end
end
