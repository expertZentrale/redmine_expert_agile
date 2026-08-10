require File.expand_path('../../test_helper', __FILE__)

# Historical state reconstruction.
#
# Every chart that shows "how things looked on day D" rests on this, so the
# cases below are hand-built timelines with known answers rather than smoke
# tests over fixtures.
class JournalProjectionTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles,
           :enabled_modules, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :issues

  Projection = RedmineExpertAgile::JournalProjection

  def setup
    @project = Project.find(1)
    User.current = User.find(1)
    @open_status = IssueStatus.where(:is_closed => false).first
    @other_open = IssueStatus.where(:is_closed => false).where.not(:id => @open_status.id).first
    @closed_status = IssueStatus.where(:is_closed => true).first
  end

  def teardown
    User.current = nil
  end

  # Midday, not midnight: the timestamps are stored in UTC and read back as
  # local dates, so an event pinned to 00:00 sits exactly on the boundary and
  # the test would assert a different day than it means to.
  def at(date)
    Time.utc(date.year, date.month, date.day, 12, 0, 0)
  end

  # Creates an issue and rewrites its timestamps so the history is deterministic.
  def issue_created_on(date, status = @open_status)
    issue = Issue.generate!(:project_id => @project.id, :status_id => status.id, :done_ratio => 0)
    issue.update_columns(:created_on => at(date), :updated_on => at(date))
    issue.reload
  end

  # Records a status/done_ratio change dated `date`.
  def change!(issue, date, attributes)
    journal = Journal.create!(:journalized => issue, :user => User.current)
    journal.update_columns(:created_on => at(date))
    attributes.each do |key, (old_value, new_value)|
      JournalDetail.create!(:journal_id => journal.id, :property => 'attr',
                            :prop_key => key.to_s,
                            :old_value => old_value, :value => new_value)
    end
    issue.update_columns(attributes.transform_values(&:last).transform_keys(&:to_s))
    issue.reload
  end

  def test_issue_without_journals_keeps_its_current_state
    issue = issue_created_on(Date.new(2026, 1, 1))
    projection = Projection.new([issue])

    state = projection.state_of(issue.id, Date.new(2026, 1, 5))

    assert_equal @open_status.id, state.status_id
    assert_not state.closed
  end

  def test_state_before_creation_is_nil
    issue = issue_created_on(Date.new(2026, 1, 10))
    projection = Projection.new([issue])

    assert_nil projection.state_of(issue.id, Date.new(2026, 1, 9))
    assert_not_nil projection.state_of(issue.id, Date.new(2026, 1, 10))
  end

  def test_state_reflects_the_status_as_of_each_date
    issue = issue_created_on(Date.new(2026, 1, 1))
    change!(issue, Date.new(2026, 1, 5),
            :status_id => [@open_status.id.to_s, @other_open.id.to_s])
    change!(issue, Date.new(2026, 1, 10),
            :status_id => [@other_open.id.to_s, @closed_status.id.to_s])
    projection = Projection.new([issue])

    assert_equal @open_status.id, projection.state_of(issue.id, Date.new(2026, 1, 4)).status_id
    assert_equal @other_open.id, projection.state_of(issue.id, Date.new(2026, 1, 5)).status_id
    assert_equal @other_open.id, projection.state_of(issue.id, Date.new(2026, 1, 9)).status_id
    assert_equal @closed_status.id, projection.state_of(issue.id, Date.new(2026, 1, 10)).status_id
    assert_equal @closed_status.id, projection.state_of(issue.id, Date.new(2026, 2, 1)).status_id
  end

  def test_closed_flag_follows_the_status
    issue = issue_created_on(Date.new(2026, 1, 1))
    change!(issue, Date.new(2026, 1, 6),
            :status_id => [@open_status.id.to_s, @closed_status.id.to_s])
    projection = Projection.new([issue])

    assert_not projection.state_of(issue.id, Date.new(2026, 1, 5)).closed
    assert projection.state_of(issue.id, Date.new(2026, 1, 6)).closed
  end

  def test_reopening_is_reflected
    issue = issue_created_on(Date.new(2026, 1, 1))
    change!(issue, Date.new(2026, 1, 5),
            :status_id => [@open_status.id.to_s, @closed_status.id.to_s])
    change!(issue, Date.new(2026, 1, 8),
            :status_id => [@closed_status.id.to_s, @open_status.id.to_s])
    projection = Projection.new([issue])

    assert projection.state_of(issue.id, Date.new(2026, 1, 6)).closed
    assert_not projection.state_of(issue.id, Date.new(2026, 1, 8)).closed
  end

  def test_several_changes_on_one_day_collapse_to_the_final_state
    issue = issue_created_on(Date.new(2026, 1, 1))
    change!(issue, Date.new(2026, 1, 5),
            :status_id => [@open_status.id.to_s, @other_open.id.to_s])
    change!(issue, Date.new(2026, 1, 5),
            :status_id => [@other_open.id.to_s, @closed_status.id.to_s])
    projection = Projection.new([issue])

    assert_equal @closed_status.id, projection.state_of(issue.id, Date.new(2026, 1, 5)).status_id
  end

  def test_done_ratio_is_tracked
    issue = issue_created_on(Date.new(2026, 1, 1))
    change!(issue, Date.new(2026, 1, 4), :done_ratio => ['0', '40'])
    change!(issue, Date.new(2026, 1, 9), :done_ratio => ['40', '100'])
    projection = Projection.new([issue])

    assert_equal 0, projection.state_of(issue.id, Date.new(2026, 1, 3)).done_ratio
    assert_equal 40, projection.state_of(issue.id, Date.new(2026, 1, 4)).done_ratio
    assert_equal 100, projection.state_of(issue.id, Date.new(2026, 1, 9)).done_ratio
  end

  def test_open_and_closed_partitions_agree_with_states
    open_issue = issue_created_on(Date.new(2026, 1, 1))
    closed_issue = issue_created_on(Date.new(2026, 1, 1))
    change!(closed_issue, Date.new(2026, 1, 3),
            :status_id => [@open_status.id.to_s, @closed_status.id.to_s])
    projection = Projection.new([open_issue, closed_issue])
    date = Date.new(2026, 1, 5)

    assert_equal [open_issue.id], projection.open_on(date).keys
    assert_equal [closed_issue.id], projection.closed_on(date).keys
    assert_equal 2, projection.states_on(date).size
  end

  def test_journals_are_read_in_a_single_query
    issues = 5.times.map { issue_created_on(Date.new(2026, 1, 1)) }
    issues.each { |i| change!(i, Date.new(2026, 1, 3), :done_ratio => ['0', '50']) }

    # The whole point of the projection: history costs one query for the entire
    # scope, not one per issue per date.
    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name] == 'SCHEMA' }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
      Projection.new(issues)
    end

    assert_operator queries, :<=, 3,
                    "expected a constant number of queries, got #{queries}"
  end
end
