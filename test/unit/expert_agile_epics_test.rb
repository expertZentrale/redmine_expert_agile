require File.expand_path('../../test_helper', __FILE__)

# Epics: which epic an issue belongs to, and what the board does with them.
class ExpertAgileEpicsTest < ActiveSupport::TestCase
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
    ExpertAgileData.delete_all
  end

  def nearest(issues)
    with_agile_settings('epic_tracker_ids' => [EPIC_TRACKER.to_s]) do
      RedmineExpertAgile::Epics.nearest(issues)
    end
  end

  def test_epics_are_off_until_a_tracker_is_chosen
    with_agile_settings('epic_tracker_ids' => '') do
      assert_not RedmineExpertAgile.epics_on?
      assert_equal({ @story.id => nil }, RedmineExpertAgile::Epics.nearest([@story]))
    end
  end

  def test_the_blank_entry_the_settings_form_posts_is_ignored
    with_agile_settings('epic_tracker_ids' => ['', EPIC_TRACKER.to_s]) do
      assert_equal [EPIC_TRACKER], RedmineExpertAgile.epic_tracker_ids
    end
  end

  def test_a_story_belongs_to_its_parent_epic
    assert_equal @epic, nearest([@story])[@story.id]
  end

  def test_a_subtask_belongs_to_the_epic_above_its_story
    assert_equal @epic, nearest([@subtask])[@subtask.id]
  end

  def test_an_issue_outside_any_epic_has_none
    result = nearest([@loose, @epic])

    assert_nil result[@loose.id]
    assert_nil result[@epic.id], 'an epic is not its own epic'
  end

  def test_the_nearest_of_nested_epics_wins
    inner = Issue.generate!(:project => @project, :tracker_id => EPIC_TRACKER, :parent_issue_id => @epic.id)
    story = Issue.generate!(:project => @project, :tracker_id => 1, :parent_issue_id => inner.id)

    assert_equal inner, nearest([story.reload])[story.id]
  end

  def test_an_epic_the_user_cannot_see_is_never_revealed
    @epic.update_column(:is_private, true)
    other = User.find(7) # not a member of the project

    result = with_agile_settings('epic_tracker_ids' => [EPIC_TRACKER.to_s]) do
      RedmineExpertAgile::Epics.nearest([@story], other)
    end

    assert_nil result[@story.id]
  end

  # Measured against one issue rather than as an absolute number: visibility
  # costs queries of its own, whatever other plugins add to it.
  def test_more_issues_cost_no_more_queries
    nearest([@story]) # warm whatever is cached per process
    one = count_queries { nearest([@story]) }
    many = count_queries { nearest([@story, @subtask, @loose]) }

    assert_equal one, many
  end

  # --- Progress --------------------------------------------------------

  def progress_of(epic)
    with_agile_settings('epic_tracker_ids' => [EPIC_TRACKER.to_s]) do
      RedmineExpertAgile::Epics.progress([epic])[epic.id]
    end
  end

  def test_progress_counts_everything_below_the_epic
    progress = progress_of(@epic)

    assert_equal 2, progress.issue_count # the story and its subtask
    assert_equal 0, progress.closed_count
    assert_equal 0, progress.percent
  end

  def test_progress_follows_story_points_where_there_are_any
    @story.expert_agile_data!.update!(:story_points => 3)
    @subtask.expert_agile_data!.update!(:story_points => 1)
    @subtask.update_column(:status_id, IssueStatus.where(:is_closed => true).first.id)

    progress = progress_of(@epic)

    assert_equal 4, progress.points
    assert_equal 1, progress.closed_points
    assert_equal 25, progress.percent
  end

  def test_progress_falls_back_to_the_issue_count
    @subtask.update_column(:status_id, IssueStatus.where(:is_closed => true).first.id)

    assert_equal 50, progress_of(@epic).percent
  end

  def test_progress_leaves_out_nested_epics_but_counts_their_stories
    inner = Issue.generate!(:project => @project, :tracker_id => EPIC_TRACKER, :parent_issue_id => @epic.id)
    Issue.generate!(:project => @project, :tracker_id => 1, :parent_issue_id => inner.id)

    assert_equal 3, progress_of(@epic.reload).issue_count
  end

  # --- The board -----------------------------------------------------

  def test_the_board_hides_epics_by_default
    with_agile_settings('epic_tracker_ids' => [EPIC_TRACKER.to_s]) do
      query = ExpertAgileQuery.new(:name => 'Board', :project => @project)
      ids = query.board_issues.map(&:id)

      assert query.hide_epics?
      assert_not_includes ids, @epic.id
      assert_includes ids, @story.id
    end
  end

  def test_the_board_shows_epics_when_asked_to
    with_agile_settings('epic_tracker_ids' => [EPIC_TRACKER.to_s]) do
      query = ExpertAgileQuery.new(:name => 'Board', :project => @project)
      query.apply_board_params(:hide_epics => '0')

      assert_includes query.board_issues.map(&:id), @epic.id
    end
  end

  def test_hiding_epics_without_epic_trackers_hides_nothing
    with_agile_settings('epic_tracker_ids' => '') do
      query = ExpertAgileQuery.new(:name => 'Board', :project => @project)

      assert_includes query.board_issues.map(&:id), @epic.id
    end
  end

  def test_the_epic_card_field_is_offered_only_with_epics_on
    with_agile_settings('epic_tracker_ids' => '') do
      names = ExpertAgileQuery.new(:project => @project).available_columns.map(&:name)
      assert_not_includes names, :epic
    end
    with_agile_settings('epic_tracker_ids' => [EPIC_TRACKER.to_s]) do
      names = ExpertAgileQuery.new(:project => @project).available_columns.map(&:name)
      assert_includes names, :epic
    end
  end

  def test_card_epics_are_loaded_for_the_whole_board_at_once
    with_agile_settings('epic_tracker_ids' => [EPIC_TRACKER.to_s]) do
      query = ExpertAgileQuery.new(:name => 'Board', :project => @project)
      query.column_names = [:tracker, :epic]
      query.board_issues

      assert_equal @epic, query.card_epic(@story)
      assert_equal 0, count_queries { query.card_epic(@subtask) }
      assert_equal @epic, query.card_epic(@subtask)
    end
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
