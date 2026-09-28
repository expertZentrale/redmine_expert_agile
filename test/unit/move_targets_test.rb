require File.expand_path('../../test_helper', __FILE__)

# The drop preview's per-card lists. Every list comes from core's
# new_statuses_allowed_to; what is tested here is that sharing answers between
# cards never hands one card another's list, and that plain cards do share.
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

  def test_lists_match_core_for_every_card
    issues = hierarchy
    targets = RedmineExpertAgile::MoveTargets.new(@user, IssueStatus.pluck(:id)).preload(issues)

    issues.each do |issue|
      expected = (issue.new_statuses_allowed_to(@user).map(&:id) | [issue.status_id]).sort
      assert_equal expected, targets.status_ids_for(issue), issue.subject
    end
  end

  def test_plain_cards_share_their_answers
    few = Array.new(2) { issue('plain') }
    many = Array.new(10) { issue('plain') }
    # The first run also pays for the user's roles and memberships, which the
    # user object keeps; compare only runs that start from the same state.
    queries_for(few)

    assert_equal queries_for(few), queries_for(many),
                 'plain cards of one tracker and status must not cost a query each'
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
    blocker = issue('blocker')
    blocked = issue('blocked')
    IssueRelation.create!(:issue_from => blocker, :issue_to => blocked,
                          :relation_type => IssueRelation::TYPE_BLOCKS)
    Issue.where(:id => [open_parent, done_parent, closed_parent, closed_child, middle, leaf,
                        blocker, blocked].map(&:id))
         .or(Issue.where(:parent_id => [open_parent.id, done_parent.id, middle.id])).to_a
  end

  def issue(subject, attributes = {})
    Issue.generate!({ :project_id => @project.id, :tracker_id => 1, :status_id => @open.id,
                      :author_id => @user.id, :subject => subject }.merge(attributes))
  end

  # Queries a board of these cards costs, preload included.
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
