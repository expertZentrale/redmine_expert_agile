require File.expand_path('../../test_helper', __FILE__)

# The epic picker on the issue form: where it is offered, which epics it
# offers, and when it only shows the epic an issue has through its parent.
class ExpertAgileEpicPickerTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles, :enabled_modules,
           :trackers, :projects_trackers, :issue_statuses, :enumerations,
           :issues, :issue_categories, :versions, :workflows

  EPIC_TRACKER = 2 # Feature request

  def setup
    @project = Project.find(1)
    @project.enable_module!(:expert_agile)
    @admin = User.find(1)
    User.current = @admin
    # The fixtures' own feature requests would be epics too.
    Issue.where(:tracker_id => EPIC_TRACKER).update_all(:tracker_id => 1)
    @checkout = Issue.generate!(:project => @project, :tracker_id => EPIC_TRACKER, :subject => 'Checkout')
    @accounts = Issue.generate!(:project => @project, :tracker_id => EPIC_TRACKER, :subject => 'Accounts')
    @story = Issue.generate!(:project => @project, :tracker_id => 1, :parent_issue_id => @checkout.id,
                             :subject => 'Pay by card')
    @subtask = Issue.generate!(:project => @project, :tracker_id => 1, :parent_issue_id => @story.id,
                               :subject => 'Card form')
    [@checkout, @accounts, @story, @subtask].each(&:reload)
  end

  def teardown
    User.current = nil
  end

  def with_epics(&block)
    with_agile_settings('epic_tracker_ids' => [EPIC_TRACKER.to_s], &block)
  end

  def new_issue(attributes = {})
    Issue.new({ :project => @project, :tracker_id => 1, :author => @admin }.merge(attributes))
  end

  def picker(issue, user = @admin)
    with_epics { RedmineExpertAgile::EpicPicker.data(issue, user) }
  end

  def offered_ids(issue, user = @admin)
    picker(issue, user)[:epics].map { |epic| epic[:id] }
  end

  # --- Where the picker is offered ----------------------------------------

  def test_a_new_issue_chooses_from_the_open_epics_by_subject
    data = picker(new_issue)

    assert_nil data[:current]
    assert_nil data[:via]
    assert_equal [@accounts.id.to_s, @checkout.id.to_s], data[:epics].map { |epic| epic[:id] }
  end

  def test_nothing_without_epics
    assert_nil RedmineExpertAgile::EpicPicker.data(new_issue, @admin)
  end

  def test_nothing_in_a_project_without_an_agile_module
    @project.disable_module!(:expert_agile)

    assert_nil picker(new_issue(:project => @project.reload))
  end

  def test_nothing_in_a_project_without_an_epic_tracker
    @project.trackers = @project.trackers.where.not(:id => EPIC_TRACKER).to_a

    assert_nil picker(new_issue(:project => @project.reload))
  end

  # An epic's parent nests epics: a decision for the parent task field.
  def test_nothing_on_an_epic
    assert_nil picker(@checkout)
    assert_nil picker(new_issue(:tracker_id => EPIC_TRACKER))
  end

  def test_nothing_for_a_user_who_may_not_set_the_parent_task
    Role.find(2).remove_permission!(:manage_subtasks)

    assert_nil picker(new_issue(:author => User.find(3)), User.find(3))
  end

  # --- Which epics -----------------------------------------------------------

  def test_a_closed_epic_is_no_choice
    @accounts.update_column(:status_id, closed_status.id)

    assert_equal [@checkout.id.to_s], offered_ids(new_issue)
  end

  def test_an_epic_of_another_project_tree_is_no_choice
    Issue.generate!(:project => Project.find(2), :tracker_id => EPIC_TRACKER, :subject => 'Elsewhere')

    assert_equal [@accounts.id.to_s, @checkout.id.to_s], offered_ids(new_issue)
  end

  def test_an_epic_the_user_cannot_see_is_no_choice
    secret = Issue.generate!(:project => @project, :tracker_id => EPIC_TRACKER, :subject => 'Secret',
                             :is_private => true)
    developer = User.find(3)

    assert_not_includes offered_ids(new_issue(:author => developer), developer), secret.id.to_s
    assert_includes offered_ids(new_issue), secret.id.to_s
  end

  # The project is named where it is not the issue's own.
  def test_an_epic_of_a_subproject_names_its_project
    sub = Issue.generate!(:project => Project.find(3), :tracker_id => EPIC_TRACKER, :subject => 'Sub epic')

    entries = picker(new_issue)[:epics].index_by { |epic| epic[:id] }
    assert_equal Project.find(3).name, entries[sub.id.to_s][:project]
    assert_nil entries[@checkout.id.to_s][:project]
  end

  # Core decides where a parent may come from.
  def test_an_epic_of_a_subproject_is_no_choice_where_subtasks_stay_in_their_project
    sub = Issue.generate!(:project => Project.find(3), :tracker_id => EPIC_TRACKER, :subject => 'Sub epic')

    with_settings(:cross_project_subtasks => '') do
      assert_not_includes offered_ids(new_issue), sub.id.to_s
    end
  end

  # An issue never goes under its own subtree.
  def test_an_epic_below_the_issue_is_no_choice
    loose = Issue.generate!(:project => @project, :tracker_id => 1, :subject => 'Loose')
    nested = Issue.generate!(:project => @project, :tracker_id => EPIC_TRACKER, :subject => 'Nested epic',
                             :parent_issue_id => loose.id)

    assert_not_includes offered_ids(loose.reload), nested.id.to_s
    assert_includes offered_ids(new_issue), nested.id.to_s
  end

  def test_an_entry_carries_the_badge_colour_and_the_progress
    Issue.generate!(:project => @project, :tracker_id => 1, :parent_issue_id => @checkout.id,
                    :status_id => closed_status.id)

    entry = picker(new_issue)[:epics].detect { |epic| epic[:id] == @checkout.id.to_s }
    assert_equal 'Checkout', entry[:subject]
    assert_equal ExpertAgileColor.for_principal(@checkout), entry[:color]
    # The story, its subtask and the closed story.
    assert_equal 3, entry[:total]
    assert_equal 1, entry[:done]
    assert_equal 33, entry[:percent]
    assert_equal false, entry[:closed]
  end

  # --- The current epic --------------------------------------------------

  def test_a_story_under_an_epic_has_it_chosen
    data = picker(@story)

    assert_equal @checkout.id.to_s, data[:current]
    assert_nil data[:via]
    assert_includes data[:epics].map { |epic| epic[:id] }, @checkout.id.to_s
  end

  # Set in the form, before the issue is saved.
  def test_a_new_issue_with_an_epic_as_parent_has_it_chosen
    assert_equal @accounts.id.to_s, picker(new_issue(:parent_issue_id => @accounts.id))[:current]
  end

  # A closed epic is no choice, but the form still names the one it has.
  def test_a_closed_current_epic_stays_on_the_list
    # Straight to the database: core refuses to close a parent with open subtasks.
    @checkout.update_column(:status_id, closed_status.id)

    data = picker(@story.reload)
    entry = data[:epics].first
    assert_equal @checkout.id.to_s, data[:current]
    assert_equal @checkout.id.to_s, entry[:id]
    assert_equal true, entry[:closed]
    assert_equal ::I18n.t(:label_closed_issues), data[:labels][:closed]
  end

  # --- Under anything else: only shown ------------------------------------

  def test_a_subtask_of_a_story_only_shows_its_epic
    data = picker(@subtask)

    assert_equal @story.id.to_s, data[:via]
    assert_equal @checkout.id.to_s, data[:current][:id]
    assert_nil data[:epics]
    assert_equal ::I18n.t(:text_expert_agile_epic_picker_via, :id => @story.id), data[:labels][:via]
  end

  def test_a_new_issue_under_a_story_only_shows_its_epic
    data = picker(new_issue(:parent_issue_id => @story.id))

    assert_equal @story.id.to_s, data[:via]
    assert_equal @checkout.id.to_s, data[:current][:id]
  end

  def test_under_an_issue_without_an_epic_it_shows_none
    loose = Issue.generate!(:project => @project, :tracker_id => 1, :subject => 'Loose')

    data = picker(new_issue(:parent_issue_id => loose.id))
    assert_equal loose.id.to_s, data[:via]
    assert_nil data[:current]
  end

  # A parent the user cannot see names no epic.
  def test_under_a_parent_the_user_cannot_see_it_shows_none
    secret = Issue.generate!(:project => @project, :tracker_id => 1, :subject => 'Secret story',
                             :is_private => true, :parent_issue_id => @checkout.id)
    developer = User.find(3)

    data = picker(new_issue(:author => developer, :parent_issue_id => secret.id), developer)
    assert_equal secret.id.to_s, data[:via]
    assert_nil data[:current]
  end

  # --- Cost ----------------------------------------------------------------

  def test_more_epics_cost_no_more_queries
    with_epics do
      RedmineExpertAgile::EpicPicker.data(new_issue, @admin) # warm whatever is cached per process
      few = count_queries { RedmineExpertAgile::EpicPicker.data(new_issue, @admin) }
      5.times { |i| Issue.generate!(:project => @project, :tracker_id => EPIC_TRACKER, :subject => "Epic #{i}") }
      many = count_queries { RedmineExpertAgile::EpicPicker.data(new_issue, @admin) }
      assert_equal few, many
    end
  end

  private

  def closed_status
    IssueStatus.where(:is_closed => true).first
  end

  def count_queries(&block)
    count = 0
    counter = lambda do |_name, _start, _finish, _id, payload|
      count += 1 unless %w(SCHEMA TRANSACTION).include?(payload[:name]) || payload[:cached]
    end
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &block)
    count
  end
end
