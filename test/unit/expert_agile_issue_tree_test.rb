require File.expand_path('../../test_helper', __FILE__)

# Epics on Redmine's issue list: when the list counts as a tree, what the
# script is told about its rows, and where the sidebar offers the epic view.
class ExpertAgileIssueTreeTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles, :enabled_modules,
           :trackers, :projects_trackers, :issue_statuses, :enumerations,
           :issues, :issue_categories, :versions, :queries

  EPIC_TRACKER = 2 # Feature request

  def setup
    @project = Project.find(1)
    @project.enable_module!(:expert_agile)
    User.current = User.find(1)
    @epic = Issue.generate!(:project => @project, :tracker_id => EPIC_TRACKER, :subject => 'Checkout')
    @story = Issue.generate!(:project => @project, :tracker_id => 1, :parent_issue_id => @epic.id,
                             :subject => 'Pay by card')
    @subtask = Issue.generate!(:project => @project, :tracker_id => 1, :parent_issue_id => @story.id,
                               :subject => 'Card form')
    @loose = Issue.generate!(:project => @project, :tracker_id => 1, :subject => 'No epic')
    [@epic, @story, @subtask].each(&:reload)
  end

  def teardown
    User.current = nil
  end

  def with_epics(&block)
    with_agile_settings('epic_tracker_ids' => [EPIC_TRACKER.to_s], &block)
  end

  def query_sorted_by(sort)
    query = IssueQuery.new(:name => '_', :project => @project)
    query.sort_criteria = sort
    query
  end

  def tree_data(issues, user = User.current)
    with_epics { RedmineExpertAgile::IssueTree.data(issues, user) }
  end

  # --- When a list is a tree ---------------------------------------------

  def test_a_list_sorted_by_parent_task_is_a_tree
    with_epics do
      assert RedmineExpertAgile::IssueTree.applies?(query_sorted_by([%w(parent asc)]))
      assert RedmineExpertAgile::IssueTree.applies?(query_sorted_by([%w(parent desc), %w(id desc)]))
    end
  end

  def test_a_list_in_any_other_order_is_left_alone
    with_epics do
      assert_not RedmineExpertAgile::IssueTree.applies?(query_sorted_by([%w(id desc)]))
      assert_not RedmineExpertAgile::IssueTree.applies?(query_sorted_by([%w(priority desc), %w(parent asc)]))
    end
  end

  def test_without_epic_trackers_no_list_is_a_tree
    assert_not RedmineExpertAgile::IssueTree.applies?(query_sorted_by([%w(parent asc)]))
  end

  # --- What the script is told -------------------------------------------

  def test_an_epic_row_carries_its_colour_and_progress
    data = tree_data([@epic, @story, @subtask])
    epic = data[:epics][@epic.id.to_s]

    assert_equal ExpertAgileColor.for_principal(@epic), epic[:color]
    assert_equal I18n.t(:label_expert_agile_epic_progress_issues, :closed => 0, :total => 2), epic[:progress]
    assert_equal RedmineExpertAgile::Epics.progress([@epic])[@epic.id].title, epic[:title]
  end

  def test_every_row_below_an_epic_belongs_to_it
    data = tree_data([@epic, @story, @subtask, @loose])

    assert_equal({ @story.id.to_s => @epic.id.to_s, @subtask.id.to_s => @epic.id.to_s }, data[:members])
  end

  # Filtered off the list, the epic still colours its stories: they keep
  # their bar, only the epic's own row and its progress are missing.
  def test_a_story_without_its_epic_on_the_page_still_gets_the_epics_colour
    data = tree_data([@story])

    assert_equal @epic.id.to_s, data[:members][@story.id.to_s]
    assert_equal({ :color => ExpertAgileColor.for_principal(@epic) }, data[:epics][@epic.id.to_s])
  end

  def test_a_page_without_epics_gets_nothing
    other = Issue.generate!(:project => @project, :tracker_id => 1, :parent_issue_id => @loose.id)

    assert_nil tree_data([@loose, other.reload])
  end

  def test_an_epic_the_user_cannot_see_is_never_revealed
    @epic.update_column(:is_private, true)

    assert_nil tree_data([@story], User.find(7))
  end

  # Measured against a small page rather than as an absolute number:
  # visibility costs queries of its own, whatever other plugins add to it.
  def test_the_page_costs_the_same_queries_whatever_its_size
    more = 5.times.map { Issue.generate!(:project => @project, :tracker_id => 1, :parent_issue_id => @epic.id) }
    rows = [@epic, @story, @subtask].map(&:reload) + more.map(&:reload)
    with_epics do
      RedmineExpertAgile::IssueTree.data(rows) # warm whatever is cached per process
      small = count_queries { RedmineExpertAgile::IssueTree.data([@epic, @story]) }
      large = count_queries { RedmineExpertAgile::IssueTree.data(rows) }

      assert_equal small, large
    end
  end

  # --- The sidebar --------------------------------------------------------

  def test_the_epic_views_are_offered_where_the_project_plans_with_epics
    with_epics { assert RedmineExpertAgile::IssueTree.views_offered?(@project) }
  end

  def test_the_planner_module_alone_is_enough
    @project.disable_module!(:expert_agile)
    @project.enable_module!(:expert_agile_backlog)

    with_epics { assert RedmineExpertAgile::IssueTree.views_offered?(@project.reload) }
  end

  def test_no_epic_views_without_the_agile_modules
    @project.disable_module!(:expert_agile)

    with_epics { assert_not RedmineExpertAgile::IssueTree.views_offered?(@project.reload) }
  end

  def test_no_epic_views_where_the_project_has_no_epic_tracker
    @project.trackers.delete(Tracker.find(EPIC_TRACKER))

    with_epics { assert_not RedmineExpertAgile::IssueTree.views_offered?(@project.reload) }
  end

  def test_no_epic_views_without_epic_trackers_or_project
    assert_not RedmineExpertAgile::IssueTree.views_offered?(@project)
    with_epics { assert_not RedmineExpertAgile::IssueTree.views_offered?(nil) }
  end

  def test_the_tree_list_shows_every_status_in_tree_order
    params = with_agile_settings('sprints_on' => '1') { RedmineExpertAgile::IssueTree.tree_list_params }

    assert_equal 'parent', params[:sort]
    assert_equal ['status_id'], params[:f]
    assert_equal({ 'status_id' => '*' }, params[:op])
    assert_equal %w(tracker status subject assigned_to expert_agile_sprint done_ratio), params[:c]
  end

  def test_the_tree_list_leaves_out_the_sprint_while_sprints_are_off
    params = with_agile_settings('sprints_on' => '0') { RedmineExpertAgile::IssueTree.tree_list_params }

    assert_not_includes params[:c], 'expert_agile_sprint'
  end

  private

  def count_queries(&block)
    count = 0
    counter = lambda do |_name, _start, _finish, _id, payload|
      count += 1 unless %w(SCHEMA TRANSACTION).include?(payload[:name]) || payload[:cached]
    end
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &block)
    count
  end
end
