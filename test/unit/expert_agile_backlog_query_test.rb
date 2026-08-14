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
end
