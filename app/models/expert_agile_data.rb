# Per-issue agile payload: board rank, story points and sprint assignment.
#
# One row per issue, created lazily — an issue that has never been ranked,
# estimated or planned carries no row at all.
class ExpertAgileData < ExpertAgileApplicationRecord
  self.table_name = 'expert_agile_data'

  belongs_to :issue
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
end
