require File.expand_path('../../test_helper', __FILE__)

# Story points: the model, the Issue accessors, and the IssueQuery column and
# filter that expose them on the core issue list.
class ExpertAgileStoryPointsTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles,
           :enabled_modules, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :issues, :issue_categories, :versions

  def setup
    @issue = Issue.find(1)
    @issue.project.enable_module!(:expert_agile)
    User.current = User.find(2)
  end

  def teardown
    User.current = nil
    ExpertAgileData.delete_all
  end

  # --- Model ---------------------------------------------------------

  def test_story_points_must_be_a_non_negative_integer
    data = ExpertAgileData.new(:issue_id => @issue.id)

    data.story_points = -1
    assert_not data.valid?
    assert data.errors[:story_points].any?

    data.story_points = 0
    assert data.valid?, data.errors.full_messages.join(', ')

    data.story_points = nil
    assert data.valid?, 'nil must be allowed — it means "not estimated"'
  end

  def test_one_row_per_issue_is_enforced
    ExpertAgileData.create!(:issue_id => @issue.id, :story_points => 3)
    duplicate = ExpertAgileData.new(:issue_id => @issue.id, :story_points => 5)

    assert_not duplicate.valid?, 'has_one assumes uniqueness; it must be validated'
  end

  # --- Issue accessors ------------------------------------------------

  def test_agile_data_row_is_created_on_demand
    assert_nil @issue.expert_agile_data

    @issue.story_points = 8
    @issue.save!

    assert_equal 8, @issue.reload.story_points
  end

  def test_story_points_are_assignable_through_safe_attributes
    @issue.safe_attributes = { 'expert_agile_data_attributes' => { 'story_points' => '5' } }
    assert @issue.save, @issue.errors.full_messages.join(', ')

    assert_equal 5, @issue.reload.story_points
  end

  def test_destroying_an_issue_destroys_its_agile_data
    @issue.story_points = 3
    @issue.save!
    assert_equal 1, ExpertAgileData.where(:issue_id => @issue.id).count

    @issue.destroy

    assert_equal 0, ExpertAgileData.where(:issue_id => @issue.id).count
  end

  def test_total_story_points_sums_the_subtree
    parent = @issue
    child = Issue.generate!(:project_id => parent.project_id, :parent_issue_id => parent.id)
    parent.reload

    parent.story_points = 2
    parent.save!
    child.story_points = 3
    child.save!

    assert_equal 5, parent.reload.total_story_points.to_i
  end

  def test_total_story_points_is_nil_when_nothing_is_estimated
    # nil and 0 must stay distinguishable: "not estimated" is not "estimated as
    # zero", and SUM over no rows is NULL rather than 0.
    assert_nil @issue.total_story_points

    @issue.story_points = 0
    @issue.save!

    assert_equal 0, @issue.reload.total_story_points.to_i
  end

  def test_story_points_available_honours_the_tracker_restriction
    with_agile_settings('story_points_on' => '1', 'trackers_for_sp' => '') do
      assert @issue.story_points_available?
    end

    with_agile_settings('story_points_on' => '1',
                        'trackers_for_sp' => (@issue.tracker_id + 1000).to_s) do
      assert_not @issue.story_points_available?
    end
  end

  # --- Ordering -------------------------------------------------------

  def test_sorted_by_rank_puts_unranked_issues_last
    ranked = Issue.generate!(:project_id => @issue.project_id)
    other = Issue.generate!(:project_id => @issue.project_id)
    ExpertAgileData.create!(:issue_id => ranked.id, :position => 10)
    ExpertAgileData.create!(:issue_id => other.id, :position => 5)

    ids = Issue.where(:id => [@issue.id, ranked.id, other.id]).sorted_by_rank.map(&:id)

    assert_equal [other.id, ranked.id, @issue.id], ids,
                 'ranked issues sort by position, unranked go last'
  end

  # --- Query column and filter ----------------------------------------

  def test_issue_query_exposes_a_story_points_column
    query = IssueQuery.new(:name => '_')

    assert_includes query.available_columns.map(&:name), :story_points
  end

  def test_issue_query_column_is_not_added_twice
    query = IssueQuery.new(:name => '_')
    query.available_columns
    names = query.available_columns.map(&:name)

    assert_equal 1, names.count(:story_points)
  end

  def test_issue_query_filters_by_story_points
    estimated = Issue.generate!(:project_id => @issue.project_id)
    estimated.story_points = 5
    estimated.save!
    unestimated = Issue.generate!(:project_id => @issue.project_id)

    query = IssueQuery.new(:name => '_')
    query.add_filter('story_points', '=', ['5'])
    ids = query.issues.map(&:id)

    assert_includes ids, estimated.id
    assert_not_includes ids, unestimated.id
  end

  def test_story_points_none_filter_matches_issues_without_a_row
    estimated = Issue.generate!(:project_id => @issue.project_id)
    estimated.story_points = 5
    estimated.save!
    unestimated = Issue.generate!(:project_id => @issue.project_id)

    query = IssueQuery.new(:name => '_')
    query.add_filter('story_points', '!*', [''])
    ids = query.issues.map(&:id)

    assert_includes ids, unestimated.id
    assert_not_includes ids, estimated.id
  end

  def test_story_points_not_equal_filter_includes_unestimated_issues
    # The interesting case: an issue with no agile_data row has no story points,
    # so "story points is not 5" must match it. A plain inner comparison would
    # drop every unestimated issue instead.
    five = Issue.generate!(:project_id => @issue.project_id)
    five.story_points = 5
    five.save!
    three = Issue.generate!(:project_id => @issue.project_id)
    three.story_points = 3
    three.save!
    unestimated = Issue.generate!(:project_id => @issue.project_id)

    query = IssueQuery.new(:name => '_')
    query.add_filter('story_points', '!', ['5'])
    ids = query.issues.map(&:id)

    assert_not_includes ids, five.id
    assert_includes ids, three.id
    assert_includes ids, unestimated.id
  end

  def test_story_points_column_is_sortable
    low = Issue.generate!(:project_id => @issue.project_id)
    low.story_points = 1
    low.save!
    high = Issue.generate!(:project_id => @issue.project_id)
    high.story_points = 9
    high.save!

    query = IssueQuery.new(:name => '_')
    query.sort_criteria = [['story_points', 'desc']]
    ids = query.issues.map(&:id)

    assert_operator ids.index(high.id), :<, ids.index(low.id)
  end
end
