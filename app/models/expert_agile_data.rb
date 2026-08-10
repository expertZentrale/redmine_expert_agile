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

  validates :issue_id, :presence => true, :uniqueness => true
  validates :story_points,
            :numericality => { :only_integer => true, :greater_than_or_equal_to => 0, :allow_nil => true }

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
