# Per-issue agile payload: board rank, story points and sprint assignment.
#
# One row per issue, created lazily — an issue that has never been ranked,
# estimated or planned carries no row at all.
class ExpertAgileData < ExpertAgileApplicationRecord
  self.table_name = 'expert_agile_data'

  belongs_to :issue, :inverse_of => :expert_agile_data
  # The sprint model arrives with the sprint feature; the constant is resolved
  # lazily, so declaring the association here is safe either way.
  belongs_to :sprint, :class_name => 'ExpertAgileSprint', :optional => true

  # The association, not the column: on a new issue the nested record is
  # validated before the issue is inserted, so issue_id is still nil while
  # inverse_of already points it at its issue. Checking the column made every
  # create with agile fields fail with "Issue cannot be blank" - from the
  # new-issue form as well as POST /issues.json (#48). The unique index on
  # issue_id still backs the uniqueness check.
  validates :issue, :presence => true
  validates :issue_id, :uniqueness => true, :allow_nil => true
  validates :story_points,
            :numericality => { :only_integer => true, :greater_than_or_equal_to => 0,
                               :less_than => 2**31, :allow_nil => true }
  # Enforced here rather than in each controller, because the issue form, the
  # bulk edit and the issue REST API all write sprint_id through nested
  # attributes and never pass through a controller of this plugin. Without it
  # any sprint id in the instance could be written onto an issue, including one
  # of a project the user cannot see, and the issue history would then print
  # that sprint's name.
  validate :sprint_available_to_issue_project, :if => :will_save_change_to_sprint_id?

  # Issues that have never been placed on a board sort last, deterministically.
  # A COALESCE sentinel (what RedmineUP uses) both defeats the index and leaves
  # unranked issues in arbitrary order relative to each other.
  scope :ranked, -> { where.not(:position => nil) }

  # The sprint lives on this row, not on Issue, so a sprint change would be
  # invisible in the issue history. Attach it to whatever journal the issue is
  # already writing, so "moved to sprint X" appears alongside the other changes
  # of that edit rather than as a separate, untraceable event.
  after_save :journalize_sprint_change, :if => :saved_change_to_sprint_id?

  private

  # The same set the backlog planner and the REST endpoint resolve against:
  # the issue project's own sprints plus those shared with it. Checked only
  # when the sprint changes, so an issue whose project has since stopped
  # sharing its sprint can still be saved for everything else.
  def sprint_available_to_issue_project
    return if sprint_id.nil?

    project = issue && issue.project
    # Open or active only: a closed sprint is finished, and planning an open
    # issue into it would rewrite its burndown and velocity after the fact —
    # and break the rule that a closed sprint holds no open issues.
    return if project && project.shared_expert_agile_sprints.available.where(:id => sprint_id).exists?

    errors.add(:sprint_id, :inclusion)
  end

  def journalize_sprint_change
    journal = issue && issue.current_journal
    return if journal.nil?

    old_value, new_value = saved_change_to_sprint_id
    journal.details << JournalDetail.new(
      :property => 'attr',
      :prop_key => 'expert_agile_sprint_id',
      :old_value => old_value,
      :value => new_value
    )
    journal.save
  end
end
