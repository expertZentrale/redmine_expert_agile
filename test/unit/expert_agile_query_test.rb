require File.expand_path('../../test_helper', __FILE__)

# The saved-board query: option round-tripping, board columns, WIP limits,
# swimlanes and the board grid.
class ExpertAgileQueryTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles,
           :enabled_modules, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :issues, :issue_categories, :versions, :queries

  def setup
    @project = Project.find(1)
    @project.enable_module!(:expert_agile)
    User.current = User.find(1) # admin, so visibility never masks a real failure
    @query = ExpertAgileQuery.new(:name => 'Board', :project => @project)
  end

  def teardown
    User.current = nil
    ExpertAgileData.delete_all
  end

  # --- Persistence and STI --------------------------------------------

  def test_is_stored_as_a_query_row
    @query.save!

    assert_equal 'ExpertAgileQuery', Query.find(@query.id).type
    assert_includes ExpertAgileQuery.only_boards.map(&:id), @query.id
  end

  def test_inherits_issue_query_filters
    # The whole reason for subclassing IssueQuery: every issue filter is there
    # without redeclaring any of them.
    names = @query.available_filters.keys

    assert_includes names, 'status_id'
    assert_includes names, 'assigned_to_id'
    assert_includes names, 'fixed_version_id'
    assert_includes names, 'story_points'
  end

  # --- Options round-tripping -----------------------------------------

  def test_board_type_defaults_to_kanban_and_rejects_junk
    assert_equal 'kanban', @query.board_type

    @query.board_type = 'scrum'
    assert_equal 'scrum', @query.board_type

    @query.board_type = 'nonsense'
    assert_equal 'kanban', @query.board_type
  end

  def test_wip_limits_round_trip_as_integer_pairs
    @query.wip_limits = { '1' => ['2', '7'], '2' => ['', '5'], '3' => ['', ''] }

    assert_equal [2, 7], @query.wip_limits[1]
    assert_equal [nil, 5], @query.wip_limits[2]
    assert_not_includes @query.wip_limits.keys, 3, 'a limit with no bounds is not a limit'
  end

  def test_wip_limits_survive_a_save_and_reload
    @query.wip_limits = { '1' => [2, 7] }
    @query.save!

    assert_equal [2, 7], ExpertAgileQuery.find(@query.id).wip_limits[1]
  end

  def test_board_status_ids_round_trip
    @query.board_status_ids = ['1', '2', 'junk', '']

    assert_equal [1, 2], @query.board_status_ids
  end

  def test_color_base_falls_back_to_the_global_setting
    with_agile_settings('color_base' => 'tracker') do
      assert_equal 'tracker', @query.color_base
    end

    @query.color_base = 'priority'
    assert_equal 'priority', @query.color_base
  end

  def test_swimlane_field_is_group_by
    @query.swimlane_field = 'assigned_to'

    assert_equal 'assigned_to', @query.group_by
    assert_equal 'assigned_to', @query.swimlane_field
  end

  # --- Visibility ------------------------------------------------------

  def test_editable_by_uses_the_agile_permissions
    role = Role.find(1)
    role.remove_permission!(:manage_public_expert_agile_queries, :add_expert_agile_queries)
    @query.visibility = Query::VISIBILITY_PUBLIC

    # Re-fetch after each permission change: a User instance memoizes the Role
    # objects it resolved, so an already-loaded user keeps the old permissions.
    assert_not @query.editable_by?(User.find(2))

    role.add_permission!(:manage_public_expert_agile_queries)

    assert @query.editable_by?(User.find(2))
  end

  # --- Columns ---------------------------------------------------------

  def test_board_statuses_default_to_open_statuses
    assert @query.board_statuses.any?
    assert @query.board_statuses.none?(&:is_closed?),
           'with no explicit selection the board shows open statuses only'
  end

  def test_board_statuses_honour_an_explicit_selection
    @query.board_status_ids = [1, 5]

    assert_equal [1, 5], @query.board_statuses.map(&:id).sort
  end

  def test_board_columns_carry_counts_and_wip_state
    status = IssueStatus.find(1)
    @query.board_status_ids = [status.id]
    @query.wip_limits = { status.id => [nil, 0] }

    column = @query.board_columns.first

    assert_equal status.id, column.id
    assert_operator column.issue_count, :>, 0, 'fixture project has issues in status 1'
    assert column.over_wip_limit?, 'a max of 0 is exceeded by any issue'
    assert_equal 'ea-wip-over', column.wip_css_class
  end

  def test_wip_limits_are_advisory_only
    # Nothing in the query layer refuses anything because of a WIP limit; the
    # column merely reports it. Guards against a future "helpful" change.
    status = IssueStatus.find(1)
    @query.board_status_ids = [status.id]
    @query.wip_limits = { status.id => [nil, 0] }

    assert @query.board_columns.first.over_wip_limit?
    assert @query.issue_board.values.flatten.any?, 'issues are still returned'
  end

  def test_board_column_path_splits_subcolumn_prefixes
    status = IssueStatus.new(:name => 'Dev: Review')
    column = RedmineExpertAgile::BoardColumn.new(:status => status)

    assert_equal %w(Dev Review), column.path
    assert_equal 'Review', column.leaf_name
  end

  def test_custom_field_columns_are_not_groupable
    # Swimlanes load their lane objects through reflect_on_association, which is
    # nil for a custom field — allowing one would raise at render time.
    assert @query.groupable_columns.none? { |c| c.is_a?(QueryCustomFieldColumn) }
  end

  # --- Board grid ------------------------------------------------------

  def test_issue_board_buckets_by_status
    @query.board_status_ids = IssueStatus.where(:is_closed => false).pluck(:id)
    board = @query.issue_board

    assert board.any?
    board.each do |(status_id), issues|
      assert issues.all? { |issue| issue.status_id == status_id }
    end
  end

  def test_issue_board_orders_cells_by_rank
    status = Issue.find(1).status
    @query.board_status_ids = [status.id]
    issues = Issue.where(:status_id => status.id, :project_id => @project.id).limit(3).to_a
    skip 'needs at least two issues in one status' if issues.size < 2

    issues.each_with_index do |issue, index|
      ExpertAgileData.create!(:issue_id => issue.id, :position => (issues.size - index) * 10)
    end

    ranked = @query.issues_for(status.id)
    positions = ranked.map { |issue| issue.expert_agile_data&.position }.compact

    assert_equal positions.sort, positions, 'cells are ordered by position ascending'
  end

  def test_issue_board_reports_truncation
    with_agile_settings('board_items_limit' => '1') do
      query = ExpertAgileQuery.new(:name => 'Board', :project => @project)
      query.board_status_ids = IssueStatus.where(:is_closed => false).pluck(:id)
      query.issue_board

      assert query.truncated?, 'a capped board must say so rather than look complete'
      assert_equal 1, query.issue_board.values.flatten.size
    end
  end

  def test_swimlanes_are_empty_without_grouping
    assert_equal [], @query.swimlanes
  end

  def test_swimlanes_load_grouped_association_records
    @query.board_status_ids = IssueStatus.where(:is_closed => false).pluck(:id)
    @query.swimlane_field = 'tracker'

    lanes = @query.swimlanes

    assert lanes.compact.any?
    assert lanes.compact.all? { |lane| lane.is_a?(Tracker) }
  end

  def test_issues_for_returns_the_cell_of_a_swimlane
    @query.board_status_ids = IssueStatus.where(:is_closed => false).pluck(:id)
    @query.swimlane_field = 'tracker'
    lane = @query.swimlanes.compact.first
    status_id = @query.board_statuses.first.id

    issues = @query.issues_for(status_id, lane)

    assert issues.all? { |issue| issue.tracker_id == lane.id && issue.status_id == status_id }
  end
end
