require File.expand_path('../../test_helper', __FILE__)

# Completing a sprint: open issues move on, the sprint closes, the target can
# become the active sprint — all of it or none of it.
class ExpertAgileSprintCompletionTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles,
           :enabled_modules, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :issues, :workflows

  def setup
    @project = Project.find(1)
    @project.enable_module!(:expert_agile)
    @project.enable_module!(:expert_agile_backlog)
    @admin = User.find(1)
    User.current = @admin
    @sprint = sprint!('Sprint 4', ExpertAgileSprint::STATUS_ACTIVE, Date.new(2026, 1, 1))
    @next = sprint!('Sprint 5', ExpertAgileSprint::STATUS_OPEN, Date.new(2026, 1, 15))
    @open_a = planned(@sprint)
    @open_b = planned(@sprint)
    @done = planned(@sprint)
    @done.update_column(:status_id, IssueStatus.where(:is_closed => true).first.id)
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
    issue.reload
  end

  def completion(user = @admin)
    RedmineExpertAgile::SprintCompletion.new(@sprint.reload, user)
  end

  def sprint_of(issue)
    ExpertAgileData.where(:issue_id => issue.id).pick(:sprint_id)
  end

  def test_open_issues_move_to_the_next_sprint_which_becomes_active
    run = completion
    assert run.complete('next', :activate => true)

    assert_equal @next.id, sprint_of(@open_a)
    assert_equal @next.id, sprint_of(@open_b)
    assert_equal @sprint.id, sprint_of(@done), 'a done issue stays in the sprint it was done in'
    assert @sprint.reload.closed?
    assert @next.reload.active?
    assert_equal [@open_a.id, @open_b.id].sort, run.moved.map(&:id).sort
  end

  def test_each_move_is_journalised
    completion.complete('next')

    detail = @open_a.reload.journals.last.details.detect { |d| d.prop_key == 'expert_agile_sprint_id' }
    assert_equal @sprint.id.to_s, detail.old_value
    assert_equal @next.id.to_s, detail.value
  end

  def test_open_issues_can_go_back_to_the_backlog
    assert completion.complete('backlog', :activate => true)

    assert_nil sprint_of(@open_a)
    assert @sprint.reload.closed?
    assert @next.reload.open?, 'nothing to activate when the issues go to the backlog'
  end

  def test_a_new_sprint_is_created_with_suggested_name_and_dates
    run = completion
    attributes = run.suggested_new_sprint_attributes
    assert_equal 'Sprint 6', attributes[:name], 'Sprint 5 is taken'
    assert_equal @next.end_date + 1, attributes[:start_date], 'after the last planned sprint'
    assert_equal attributes[:start_date] + 13, attributes[:end_date]

    assert run.complete('new', :activate => true, :new_sprint_attributes => attributes)

    created = ExpertAgileSprint.find_by(:name => 'Sprint 6')
    assert created.active?
    assert_equal created.id, sprint_of(@open_a)
  end

  def test_activating_stands_the_completed_sprint_down_cleanly
    completion.complete('next', :activate => true)

    assert_equal [@next.id], ExpertAgileSprint.where(:project_id => @project.id).active.pluck(:id)
  end

  def test_one_issue_that_cannot_move_writes_nothing
    # The target is not offered to this issue's project: sharing left out.
    elsewhere = Project.find(2)
    elsewhere.enable_module!(:expert_agile_backlog)
    stranger = Issue.generate!(:project => elsewhere)
    # Kept from before the sharing changed: the row is not re-validated.
    ExpertAgileData.new(:issue => stranger, :sprint_id => @sprint.id).save(:validate => false)

    run = completion
    assert_not run.complete('next', :activate => true)

    assert_equal [stranger.id], run.refusals.map { |r| r.issue.id }
    assert_equal @sprint.id, sprint_of(@open_a), 'the movable issues stay as well'
    assert @sprint.reload.active?
    assert @next.reload.open?
  end

  def test_a_user_who_may_not_plan_is_refused_per_issue
    user = User.find(2)
    Role.find(1).add_permission!(:view_issues, :edit_issues)
    Role.find(1).remove_permission!(:manage_expert_agile_backlog)

    run = completion(user)
    assert_not run.complete('next')

    assert_equal [@open_a.id, @open_b.id].sort, run.refusals.map { |r| r.issue.id }.sort
    assert_equal @sprint.id, sprint_of(@open_a)
  end

  def test_an_unknown_target_is_refused
    run = completion
    assert_not run.complete('999999')

    assert run.sprint.errors.full_messages.any?
    assert @sprint.reload.active?
  end

  def test_next_means_no_sprint_when_there_is_none
    @next.destroy
    run = completion

    assert_nil run.next_sprint
    assert_not run.complete('next')
  end

  def test_an_invalid_new_sprint_writes_nothing
    run = completion
    assert_not run.complete('new', :new_sprint_attributes => { :name => '' })

    assert_equal @sprint.id, sprint_of(@open_a)
    assert run.new_sprint.errors.any?
    assert_equal 2, ExpertAgileSprint.count, 'the invalid new sprint was not kept'
  end
end
