require File.expand_path('../../test_helper', __FILE__)

# The drop preview's per-card lists. The list itself always comes from core's
# new_statuses_allowed_to; what is tested here is that the batched hierarchy
# checks used for memoising agree with core, and that they are batched.
class MoveTargetsTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :enabled_modules, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :issues, :workflows

  def setup
    @project = Project.find(1)
    @user = User.find(2)
    User.current = @user
    @open = IssueStatus.where(:is_closed => false).sorted.first
    @closed = IssueStatus.where(:is_closed => true).sorted.first
  end

  def test_hierarchy_answers_match_core
    issues = hierarchy
    targets = RedmineExpertAgile::MoveTargets.new(@user, IssueStatus.pluck(:id)).preload(issues)

    issues.each do |issue|
      assert_equal issue.closable?, targets.send(:closable?, issue), "closable? for #{issue.subject}"
      assert_equal issue.reopenable?, targets.send(:reopenable?, issue), "reopenable? for #{issue.subject}"
    end
  end

  def test_lists_match_core_for_every_card
    issues = hierarchy
    targets = RedmineExpertAgile::MoveTargets.new(@user, IssueStatus.pluck(:id)).preload(issues)

    issues.each do |issue|
      expected = (issue.new_statuses_allowed_to(@user).map(&:id) | [issue.status_id]).sort
      assert_equal expected, targets.status_ids_for(issue), issue.subject
    end
  end

  def test_parents_and_subtasks_do_not_cost_a_query_each
    small = Array.new(2) { family }.flatten
    large = Array.new(8) { family }.flatten

    assert_equal queries_for(small), queries_for(large),
                 'hierarchy lookups must be batched, not asked per parent or subtask'
  end

  private

  # A parent with an open subtask, a parent whose subtasks are all closed, a
  # closed parent with a closed subtask (which cannot be reopened), a
  # grandchild under an open chain, and a plain leaf.
  def hierarchy
    open_parent = issue('open parent')
    issue('open child', :parent_issue_id => open_parent.id)

    done_parent = issue('done parent')
    issue('closed child', :parent_issue_id => done_parent.id, :status_id => @closed.id)

    closed_parent = issue('closed parent')
    closed_child = issue('child of a closed parent', :parent_issue_id => closed_parent.id,
                                                      :status_id => @closed.id)
    closed_parent.reload.update!(:status_id => @closed.id)

    middle = issue('middle', :parent_issue_id => open_parent.id)
    issue('grandchild', :parent_issue_id => middle.id)

    leaf = issue('leaf')
    Issue.where(:id => [open_parent, done_parent, closed_parent, closed_child, middle, leaf].map(&:id))
         .or(Issue.where(:parent_id => [open_parent.id, done_parent.id, middle.id])).to_a
  end

  def family
    parent = issue('parent')
    [parent.reload, issue('child', :parent_issue_id => parent.id)]
  end

  def issue(subject, attributes = {})
    Issue.generate!({ :project_id => @project.id, :tracker_id => 1, :status_id => @open.id,
                      :author_id => @user.id, :subject => subject }.merge(attributes))
  end

  # Counts the queries a board of these cards costs once the workflow answers
  # for their tracker/status are memoised: the preload plus one lookup per card.
  def queries_for(issues)
    issues = Issue.where(:id => issues.map(&:id)).to_a
    count = 0
    counter = lambda do |*, payload|
      count += 1 unless payload[:name] == 'SCHEMA' || payload[:cached]
    end
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
      targets = RedmineExpertAgile::MoveTargets.new(@user, IssueStatus.pluck(:id)).preload(issues)
      issues.each { |issue| targets.status_ids_for(issue) }
    end
    count
  end
end
