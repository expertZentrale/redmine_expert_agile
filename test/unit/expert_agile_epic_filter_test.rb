require File.expand_path('../../test_helper', __FILE__)

# The epic filter: on the issue list, the board, the planner and the charts,
# since all of them are IssueQueries.
class ExpertAgileEpicFilterTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles, :enabled_modules,
           :trackers, :projects_trackers, :issue_statuses, :enumerations,
           :issues, :issue_categories, :versions

  EPIC_TRACKER = 2 # Feature request

  def setup
    @project = Project.find(1)
    @project.enable_module!(:expert_agile)
    @project.enable_module!(:expert_agile_backlog)
    User.current = User.find(1)
    @checkout = epic!('Checkout')
    @story = issue!(@checkout, 'Pay by card')
    @subtask = issue!(@story, 'Card form')
    @nested = epic!('Wallets', @checkout)
    @nested_story = issue!(@nested, 'Pay by wallet')
    @search = epic!('Search')
    @search_story = issue!(@search, 'Suggestions')
    @loose = Issue.generate!(:project => @project, :tracker_id => 1, :subject => 'No epic')
  end

  def teardown
    User.current = nil
    ExpertAgileData.delete_all
  end

  def epic!(subject, parent = nil)
    Issue.generate!(:project => @project, :tracker_id => EPIC_TRACKER, :subject => subject,
                    :parent_issue_id => parent && parent.id)
  end

  def issue!(parent, subject)
    Issue.generate!(:project => @project, :tracker_id => 1, :subject => subject, :parent_issue_id => parent.id)
  end

  def ours
    [@checkout, @story, @subtask, @nested, @nested_story, @search, @search_story, @loose].map(&:id)
  end

  def ids_for(operator, values, query_class = IssueQuery)
    with_agile_settings('epic_tracker_ids' => [EPIC_TRACKER.to_s]) do
      query = query_class.new(:name => '_', :project => @project)
      query.add_filter('expert_agile_epic_id', operator, values)
      query.issues.map(&:id) & ours
    end
  end

  def test_one_epic_brings_everything_below_it
    ids = ids_for('=', [@checkout.id.to_s])

    assert_equal [@story, @subtask, @nested, @nested_story].map(&:id).sort, ids.sort
  end

  def test_several_epics
    ids = ids_for('=', [@nested.id.to_s, @search.id.to_s])

    assert_equal [@nested_story, @search_story].map(&:id).sort, ids.sort
  end

  def test_not_in_an_epic_keeps_everything_else
    ids = ids_for('!', [@checkout.id.to_s])

    assert_equal [@checkout, @search, @search_story, @loose].map(&:id).sort, ids.sort
  end

  def test_any_and_no_epic
    assert_equal [@story, @subtask, @nested, @nested_story, @search_story].map(&:id).sort,
                 ids_for('*', ['']).sort
    assert_equal [@checkout, @search, @loose].map(&:id).sort, ids_for('!*', ['']).sort
  end

  def test_junk_values_match_nothing
    assert_empty ids_for('=', ['abc', ''])
    assert_equal ours.sort, ids_for('!', ['abc']).sort
    assert_empty ids_for('=', [@loose.id.to_s]), 'an issue that is no epic is no epic filter value'
  end

  # An epic the user may not see neither matches by a crafted id nor counts
  # as "any epic": the filter must not tell which readable issues sit under it.
  def test_an_epic_the_user_cannot_see_counts_for_nothing
    @search.update_column(:is_private, true)
    User.current = User.find(7) # not a member: sees the public project's public issues

    assert_empty ids_for('=', [@search.id.to_s])
    assert_not_includes ids_for('*', ['']), @search_story.id
    assert_includes ids_for('!*', ['']), @search_story.id
  end

  def test_the_filter_offers_the_open_epics_of_the_project
    @search.update_column(:status_id, IssueStatus.where(:is_closed => true).first.id)
    values = with_agile_settings('epic_tracker_ids' => [EPIC_TRACKER.to_s]) do
      IssueQuery.new(:name => '_', :project => @project).available_filters['expert_agile_epic_id'][:values]
    end

    assert_includes values, ["Checkout (##{@checkout.id})", @checkout.id.to_s]
    assert_includes values.map(&:last), @nested.id.to_s
    assert_not_includes values.map(&:last), @search.id.to_s, 'closed epics are not offered'
    assert_not_includes values.map(&:last), @story.id.to_s
  end

  def test_a_cross_project_list_names_each_epics_project
    values = with_agile_settings('epic_tracker_ids' => [EPIC_TRACKER.to_s]) do
      IssueQuery.new(:name => '_').available_filters['expert_agile_epic_id'][:values]
    end

    assert_includes values, ["#{@project.name} » Checkout (##{@checkout.id})", @checkout.id.to_s]
  end

  def test_no_filter_without_epic_trackers_or_without_the_plugin
    with_agile_settings('epic_tracker_ids' => '') do
      assert_nil IssueQuery.new(:name => '_', :project => @project).available_filters['expert_agile_epic_id']
    end
    with_agile_settings('epic_tracker_ids' => [EPIC_TRACKER.to_s]) do
      assert_nil IssueQuery.new(:name => '_', :project => Project.find(2)).available_filters['expert_agile_epic_id']
    end
  end

  def test_the_board_and_the_planner_filter_the_same_way
    assert_equal [@story, @subtask, @nested, @nested_story].map(&:id).sort,
                 ids_for('=', [@checkout.id.to_s], ExpertAgileQuery).sort

    backlog = with_agile_settings('epic_tracker_ids' => [EPIC_TRACKER.to_s]) do
      query = ExpertAgileBacklogQuery.new(:name => '_', :project => @project)
      query.add_filter('expert_agile_epic_id', '=', [@nested.id.to_s, @search.id.to_s])
      query.backlog_issues.map(&:id) & ours
    end
    assert_equal [@nested_story, @search_story].map(&:id).sort, backlog.sort
  end
end
