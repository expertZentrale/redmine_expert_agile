require File.expand_path('../../test_helper', __FILE__)

class ExpertAgileSprintTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles,
           :enabled_modules, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :issues

  def setup
    @project = Project.find(1)
    User.current = User.find(1)
  end

  def teardown
    User.current = nil
    ExpertAgileData.delete_all
    ExpertAgileSprint.delete_all
  end

  def build_sprint(attributes = {})
    ExpertAgileSprint.new({
      :project => @project,
      :name => 'Sprint 1',
      :start_date => Date.new(2026, 1, 1),
      :end_date => Date.new(2026, 1, 14)
    }.merge(attributes))
  end

  # --- Validations ------------------------------------------------------

  def test_requires_name_and_dates
    sprint = ExpertAgileSprint.new(:project => @project)

    assert_not sprint.valid?
    assert sprint.errors[:name].any?
    assert sprint.errors[:start_date].any?
    assert sprint.errors[:end_date].any?
  end

  def test_end_date_must_not_precede_start_date
    sprint = build_sprint(:end_date => Date.new(2025, 12, 1))

    assert_not sprint.valid?
    assert sprint.errors[:end_date].any?
  end

  def test_end_date_may_equal_start_date
    assert build_sprint(:end_date => Date.new(2026, 1, 1)).valid?
  end

  def test_name_is_unique_per_project
    build_sprint.save!
    duplicate = build_sprint(:start_date => Date.new(2026, 3, 1), :end_date => Date.new(2026, 3, 14))

    assert_not duplicate.valid?
    assert duplicate.errors[:name].any?
  end

  def test_same_name_is_allowed_in_another_project
    build_sprint.save!
    other = build_sprint(:project => Project.find(2))

    assert other.valid?, other.errors.full_messages.join(', ')
  end

  def test_overlapping_sprints_are_rejected
    build_sprint.save!
    overlapping = build_sprint(:name => 'Sprint 2',
                               :start_date => Date.new(2026, 1, 10),
                               :end_date => Date.new(2026, 1, 24))

    assert_not overlapping.valid?
    assert overlapping.errors[:base].any?
  end

  def test_adjacent_sprints_are_allowed
    build_sprint.save!
    adjacent = build_sprint(:name => 'Sprint 2',
                            :start_date => Date.new(2026, 1, 15),
                            :end_date => Date.new(2026, 1, 28))

    assert adjacent.valid?, adjacent.errors.full_messages.join(', ')
  end

  def test_overlap_can_be_allowed_by_setting
    build_sprint.save!
    with_agile_settings('allow_overlapping_sprints' => '1') do
      overlapping = build_sprint(:name => 'Sprint 2',
                                 :start_date => Date.new(2026, 1, 10),
                                 :end_date => Date.new(2026, 1, 24))

      assert overlapping.valid?, overlapping.errors.full_messages.join(', ')
    end
  end

  def test_a_sprint_does_not_overlap_itself
    sprint = build_sprint
    sprint.save!
    sprint.name = 'Renamed'

    assert sprint.valid?, sprint.errors.full_messages.join(', ')
  end

  def test_cannot_close_a_sprint_with_open_issues
    sprint = build_sprint
    sprint.save!
    issue = Issue.generate!(:project_id => @project.id)
    ExpertAgileData.create!(:issue_id => issue.id, :sprint_id => sprint.id)

    sprint.status = ExpertAgileSprint::STATUS_CLOSED

    assert_not sprint.valid?
    assert sprint.errors[:base].any?
  end

  def test_can_close_a_sprint_once_its_issues_are_closed
    sprint = build_sprint
    sprint.save!
    issue = Issue.generate!(:project_id => @project.id)
    ExpertAgileData.create!(:issue_id => issue.id, :sprint_id => sprint.id)
    issue.status = IssueStatus.where(:is_closed => true).first
    issue.save!

    sprint.status = ExpertAgileSprint::STATUS_CLOSED

    assert sprint.valid?, sprint.errors.full_messages.join(', ')
  end

  # --- Lifecycle --------------------------------------------------------

  def test_activating_a_sprint_stands_the_others_down
    first = build_sprint(:status => ExpertAgileSprint::STATUS_ACTIVE)
    first.save!
    second = build_sprint(:name => 'Sprint 2',
                          :start_date => Date.new(2026, 2, 1), :end_date => Date.new(2026, 2, 14),
                          :status => ExpertAgileSprint::STATUS_ACTIVE)
    second.save!

    assert_equal ExpertAgileSprint::STATUS_OPEN, first.reload.status
    assert_equal ExpertAgileSprint::STATUS_ACTIVE, second.reload.status
    assert_equal second, @project.reload.active_expert_agile_sprint
  end

  def test_length_and_remaining_days
    sprint = build_sprint

    assert_equal 14, sprint.length
    assert_equal 0, sprint.remaining_days(Date.new(2026, 2, 1)), 'never negative'
    assert_equal 4, sprint.remaining_days(Date.new(2026, 1, 10))
  end

  def test_destroying_a_sprint_unassigns_its_issues_without_deleting_them
    sprint = build_sprint
    sprint.save!
    issue = Issue.generate!(:project_id => @project.id)
    ExpertAgileData.create!(:issue_id => issue.id, :sprint_id => sprint.id)

    sprint.destroy

    assert Issue.exists?(issue.id), 'the issue survives its sprint'
    assert_nil ExpertAgileData.find_by(:issue_id => issue.id).sprint_id
  end

  # --- Sharing ----------------------------------------------------------

  def test_unshared_sprint_belongs_to_its_project_only
    sprint = build_sprint
    sprint.save!

    assert sprint.shared_with?(@project)
    assert_not sprint.shared_with?(Project.find(2))
    assert_includes @project.shared_expert_agile_sprints, sprint
    assert_not_includes Project.find(2).shared_expert_agile_sprints, sprint
  end

  def test_system_shared_sprint_reaches_every_project
    sprint = build_sprint(:sharing => ExpertAgileSprint::SHARING_SYSTEM)
    sprint.save!

    assert sprint.shared_with?(Project.find(2))
    assert_includes Project.find(2).shared_expert_agile_sprints, sprint
  end

  def test_descendant_shared_sprint_reaches_subprojects_only
    parent = Project.find(1)
    child = Project.find(3) # subproject of 1 in the fixtures
    assert_equal parent.id, child.parent_id, 'fixture assumption: project 3 is a child of 1'

    sprint = build_sprint(:project => parent, :sharing => ExpertAgileSprint::SHARING_DESCENDANTS)
    sprint.save!

    assert sprint.shared_with?(child)
    assert_includes child.shared_expert_agile_sprints, sprint
    assert_not_includes Project.find(2).shared_expert_agile_sprints, sprint
  end

  def test_sharing_is_symmetric_between_both_directions
    # shared_projects (sprint -> projects) and shared_expert_agile_sprints
    # (project -> sprints) are two separate queries; they must agree.
    sprint = build_sprint(:sharing => ExpertAgileSprint::SHARING_TREE)
    sprint.save!

    sprint.shared_projects.each do |project|
      assert_includes project.shared_expert_agile_sprints, sprint,
                      "#{project.identifier} is in shared_projects but not the inverse"
    end
  end

  # --- Scopes -----------------------------------------------------------

  def test_sorted_puts_active_first_then_open_then_closed
    open_sprint = build_sprint(:name => 'Open', :status => ExpertAgileSprint::STATUS_OPEN)
    open_sprint.save!
    active = build_sprint(:name => 'Active', :status => ExpertAgileSprint::STATUS_ACTIVE,
                          :start_date => Date.new(2026, 2, 1), :end_date => Date.new(2026, 2, 14))
    active.save!
    closed = build_sprint(:name => 'Closed', :status => ExpertAgileSprint::STATUS_CLOSED,
                          :start_date => Date.new(2025, 1, 1), :end_date => Date.new(2025, 1, 14))
    closed.save!

    assert_equal %w(Active Open Closed), ExpertAgileSprint.sorted.map(&:name)
  end

  def test_available_excludes_closed_sprints
    build_sprint(:name => 'Open').save!
    build_sprint(:name => 'Closed', :status => ExpertAgileSprint::STATUS_CLOSED,
                 :start_date => Date.new(2025, 1, 1), :end_date => Date.new(2025, 1, 14)).save!

    assert_equal ['Open'], ExpertAgileSprint.available.map(&:name)
  end

  # --- Journalling ------------------------------------------------------

  def test_sprint_change_is_recorded_in_the_issue_journal
    # The sprint lives on expert_agile_data, so without this it would change
    # silently and never appear in the issue history.
    sprint = build_sprint
    sprint.save!
    issue = Issue.generate!(:project_id => @project.id)

    issue.init_journal(User.current, 'Planning')
    issue.expert_agile_data!.sprint_id = sprint.id
    issue.save!

    detail = issue.reload.journals.last.details.detect { |d| d.prop_key == 'expert_agile_sprint_id' }
    assert_not_nil detail, 'the sprint change must be journalled'
    assert_equal sprint.id.to_s, detail.value.to_s
  end
end
