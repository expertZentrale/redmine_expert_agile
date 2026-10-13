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

  # A second completion that loaded the sprint before the first one closed
  # it: the row lock makes it see the sprint as it now is.
  def test_a_completion_racing_another_finds_the_sprint_closed
    stale = completion
    ExpertAgileSprint.where(:id => @sprint.id).update_all(:status => ExpertAgileSprint::STATUS_CLOSED)

    assert_not stale.complete('backlog')
    assert_equal @sprint.id, sprint_of(@open_a), 'nothing moved'
    assert_includes stale.sprint.errors.full_messages, I18n.t(:error_expert_agile_sprint_already_closed)
  end

  def test_activating_a_sprint_shared_from_another_project_needs_its_permission
    parent_sprint = ExpertAgileSprint.create!(:project => @project, :name => 'Shared',
                                              :sharing => ExpertAgileSprint::SHARING_DESCENDANTS,
                                              :start_date => Date.new(2026, 3, 1), :end_date => Date.new(2026, 3, 14))
    child = Project.find(3)
    child.enable_module!(:expert_agile)
    child.enable_module!(:expert_agile_backlog)
    own = ExpertAgileSprint.create!(:project => child, :name => 'Child sprint', :status => ExpertAgileSprint::STATUS_ACTIVE,
                                    :start_date => Date.new(2026, 1, 1), :end_date => Date.new(2026, 1, 14))
    user = User.find(2)
    Role.find(1).add_permission!(:manage_expert_agile_sprints, :manage_expert_agile_backlog, :edit_issues)
    Member.create!(:project => child, :principal => user, :role_ids => [1]) unless child.users.include?(user)
    Role.find(1).remove_permission!(:manage_expert_agile_sprints) # none anywhere now, so not in project 1
    Role.create!(:name => 'Child sprint manager', :permissions => [:manage_expert_agile_sprints, :manage_expert_agile_backlog,
                                                                 :edit_issues, :view_issues]).tap do |role|
      Member.where(:project_id => child.id, :user_id => user.id).first.roles << role
    end

    run = RedmineExpertAgile::SprintCompletion.new(own, user)
    assert_not run.complete(parent_sprint.id.to_s, :activate => true)
    assert_includes run.sprint.errors.full_messages, I18n.t(:error_expert_agile_sprint_complete_activate_foreign)
    assert parent_sprint.reload.open?
    assert own.reload.active?
  end

  def test_the_suggested_name_skips_a_name_taken_in_another_case
    @next.update_column(:name, 'SPRINT 5')

    assert_equal 'Sprint 6', completion.suggested_new_sprint_attributes[:name]
  end

  def test_counts_shown_cover_only_issues_the_user_may_see
    hidden = planned(@sprint)
    hidden.update_column(:is_private, true)
    user = User.find(3) # a developer: sees every issue but private ones
    Role.find(2).add_permission!(:view_issues)

    run = RedmineExpertAgile::SprintCompletion.new(@sprint.reload, user)

    assert_not_includes run.visible_open_issues.map(&:id), hidden.id
    assert_includes run.open_issues.map(&:id), hidden.id, 'the move still covers it'
  end

  def test_a_target_closed_meanwhile_is_refused
    stale = completion
    stale.next_sprint # looked up now ...
    ExpertAgileSprint.where(:id => @next.id).update_all(:status => ExpertAgileSprint::STATUS_CLOSED) # ... closed since

    assert_not stale.complete('next', :activate => true)
    assert @next.reload.closed?
    assert_equal @sprint.id, sprint_of(@open_a)
  end

  # A done issue stays in its completed sprint; reopened, it leaves it.
  def test_reopening_an_issue_takes_it_out_of_a_closed_sprint
    completion.complete('next')
    assert_equal @sprint.id, sprint_of(@done)

    @done.reload.init_journal(@admin)
    @done.status_id = IssueStatus.where(:is_closed => false).first.id
    @done.save!

    assert_nil sprint_of(@done)
    detail = @done.journals.last.details.detect { |d| d.prop_key == 'expert_agile_sprint_id' }
    assert_equal @sprint.id.to_s, detail.old_value
    assert_nil detail.value
  end

  def test_reopening_an_issue_of_an_open_sprint_keeps_it_there
    @open_a.update_column(:status_id, IssueStatus.where(:is_closed => true).first.id)
    @open_a.reload.status_id = IssueStatus.where(:is_closed => false).first.id
    @open_a.save!

    assert_equal @sprint.id, sprint_of(@open_a)
  end

  def test_a_target_deleted_meanwhile_is_a_refusal
    stale = completion
    stale.next_sprint
    ExpertAgileSprint.where(:id => @next.id).delete_all

    assert_not stale.complete('next')
    assert_includes stale.sprint.errors.full_messages, I18n.t(:error_expert_agile_sprint_complete_target)
    assert_equal @sprint.id, sprint_of(@open_a)
  end

  def test_a_sprint_deleted_meanwhile_is_a_refusal
    stale = completion
    ExpertAgileSprint.where(:id => @sprint.id).delete_all

    assert_not stale.complete('backlog')
    assert_includes stale.sprint.errors.full_messages, I18n.t(:error_expert_agile_sprint_complete_gone)
  end

  # One entry however many hidden issues there are: a count per entry
  # would tell how many the user cannot see.
  def test_hidden_issues_are_refused_together_without_their_number
    2.times do
      hidden = planned(@sprint)
      hidden.update_column(:is_private, true)
    end
    user = User.find(3)
    Role.find(2).add_permission!(:view_issues, :edit_issues, :manage_expert_agile_backlog)

    run = RedmineExpertAgile::SprintCompletion.new(@sprint.reload, user)
    assert_not run.complete('backlog')

    hidden_refusals = run.refusals.select { |refusal| refusal.issue.nil? }
    assert_equal 1, hidden_refusals.size
  end

  def test_activating_a_sprint_stands_every_other_one_down
    other = sprint!('Sprint 6', ExpertAgileSprint::STATUS_OPEN, Date.new(2026, 2, 1))
    other.update!(:status => ExpertAgileSprint::STATUS_ACTIVE)

    assert_equal [other.id], ExpertAgileSprint.where(:project_id => @project.id).active.pluck(:id)
  end
end
