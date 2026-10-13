require File.expand_path('../../test_helper', __FILE__)

# The sprint on the core issue list: a filter (with "active sprint", "any",
# "none") and a column that sorts by start date and groups by sprint.
class ExpertAgileSprintFilterTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles,
           :enabled_modules, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :issues, :issue_categories, :versions

  def setup
    @project = Project.find(1)
    @project.enable_module!(:expert_agile)
    User.current = User.find(1)
    @active = sprint!('Sprint A', ExpertAgileSprint::STATUS_ACTIVE, Date.new(2026, 1, 1))
    @next = sprint!('Sprint B', ExpertAgileSprint::STATUS_OPEN, Date.new(2026, 1, 15))
    @in_active = planned(@active)
    @in_next = planned(@next)
    @unplanned = Issue.generate!(:project => @project)
  end

  def teardown
    User.current = nil
    ExpertAgileData.delete_all
    ExpertAgileSprint.delete_all
  end

  def sprint!(name, status, start)
    ExpertAgileSprint.create!(:project => @project, :name => name, :status => status,
                              :start_date => start, :end_date => start + 13)
  end

  def planned(sprint)
    issue = Issue.generate!(:project => @project)
    issue.expert_agile_data!.update!(:sprint_id => sprint.id)
    issue
  end

  def ids_for(operator, values)
    query = IssueQuery.new(:name => '_', :project => @project)
    query.add_filter('expert_agile_sprint_id', operator, values)
    query.issues.map(&:id)
  end

  def test_filters_by_one_sprint
    ids = ids_for('=', [@next.id.to_s])

    assert_equal [@in_next.id], ids & [@in_active.id, @in_next.id, @unplanned.id]
  end

  def test_the_active_sprint_is_resolved_when_the_query_runs
    assert_includes ids_for('=', ['active']), @in_active.id

    @active.update!(:status => ExpertAgileSprint::STATUS_OPEN)
    @next.update!(:status => ExpertAgileSprint::STATUS_ACTIVE)

    ids = ids_for('=', ['active'])
    assert_includes ids, @in_next.id
    assert_not_includes ids, @in_active.id
  end

  def test_not_in_a_sprint_keeps_issues_never_planned
    ids = ids_for('!', [@active.id.to_s])

    assert_includes ids, @unplanned.id
    assert_includes ids, @in_next.id
    assert_not_includes ids, @in_active.id
  end

  def test_any_and_none
    any = ids_for('*', [''])
    none = ids_for('!*', [''])

    assert_includes any, @in_active.id
    assert_not_includes any, @unplanned.id
    assert_includes none, @unplanned.id
    assert_not_includes none, @in_next.id
  end

  def test_active_with_no_active_sprint_matches_nothing
    @active.update!(:status => ExpertAgileSprint::STATUS_OPEN)

    assert_empty ids_for('=', ['active']) & [@in_active.id, @in_next.id, @unplanned.id]
  end

  def test_the_filter_offers_the_active_sprint_and_the_projects_sprints
    query = IssueQuery.new(:name => '_', :project => @project)
    values = query.available_filters['expert_agile_sprint_id'][:values].map(&:last)

    assert_equal 'active', values.first
    assert_includes values, @active.id.to_s
    assert_includes values, @next.id.to_s
  end

  def test_a_project_without_the_plugin_gets_neither_filter_nor_column
    other = Project.find(2)
    query = IssueQuery.new(:name => '_', :project => other)

    assert_nil query.available_filters['expert_agile_sprint_id']
    assert_not_includes query.available_columns.map(&:name), :expert_agile_sprint
  end

  def test_the_column_shows_sorts_and_groups_by_sprint
    query = IssueQuery.new(:name => '_', :project => @project)
    column = query.available_columns.detect { |c| c.name == :expert_agile_sprint }

    assert_equal 'Sprint A', column.value(@in_active)
    assert_nil column.value(@unplanned)

    query.add_filter('expert_agile_sprint_id', '*', [''])
    query.sort_criteria = [['expert_agile_sprint', 'desc']]
    ordered = query.issues.map(&:id) & [@in_active.id, @in_next.id]
    assert_equal [@in_next.id, @in_active.id], ordered

    query.group_by = 'expert_agile_sprint'
    counts = query.result_count_by_group
    assert_equal 1, counts[@active]
    assert_equal 1, counts[@next]
    assert_equal @active, column.group_value(@in_active)
  end

  # Names are unique only within a project; a cross-project list must not
  # merge two projects' "Sprint A" into one group.
  def test_same_named_sprints_of_two_projects_stay_two_groups
    other = Project.find(2)
    other.enable_module!(:expert_agile)
    twin = ExpertAgileSprint.create!(:project => other, :name => 'Sprint A',
                                     :start_date => Date.new(2026, 2, 1), :end_date => Date.new(2026, 2, 14))
    elsewhere = Issue.generate!(:project => other)
    elsewhere.expert_agile_data!.update!(:sprint_id => twin.id)

    query = IssueQuery.new(:name => '_')
    query.add_filter('expert_agile_sprint_id', '*', [''])
    query.group_by = 'expert_agile_sprint'
    counts = query.result_count_by_group

    assert_equal 1, counts[@active]
    assert_equal 1, counts[twin]
  end

  def test_the_column_costs_no_query_per_row
    query = IssueQuery.new(:name => '_', :project => @project)
    query.column_names = [:subject, :expert_agile_sprint, :story_points]
    column = query.available_columns.detect { |c| c.name == :expert_agile_sprint }
    rows = query.issues

    count = 0
    counter = ->(*, payload) { count += 1 unless %w(SCHEMA TRANSACTION).include?(payload[:name]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
      rows.each { |issue| column.value(issue); issue.story_points }
    end

    assert_equal 0, count
  end
end
