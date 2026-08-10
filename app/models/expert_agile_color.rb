# A card colour, attached polymorphically to whatever the board colours by.
#
# One row per container, enforced by a unique index on
# (container_type, container_id).
class ExpertAgileColor < ExpertAgileApplicationRecord
  self.table_name = 'expert_agile_colors'

  # A fixed, named palette rather than free hex entry: the values are also used
  # as CSS class suffixes, every one is contrast-checked against the card text
  # colour in expert_agile.css, and a closed set keeps boards legible when
  # several people colour things independently.
  COLORS = %w(green blue turquoise light_green yellow orange red purple gray).freeze

  # What the admin screen offers, keyed by the name that appears in the URL.
  # Resolving through this map is what stops `Object.const_get(params[...])`
  # from being reachable at all — RedmineUP does exactly that const_get on user
  # input and relies on a later respond_to? check to limit the damage.
  COLORABLE_CLASSES = {
    'issue' => 'Issue',
    'project' => 'Project',
    'tracker' => 'Tracker',
    'issue_priority' => 'IssuePriority',
    'issue_status' => 'IssueStatus'
  }.freeze

  # The values actually stored in container_type. IssuePriority is an STI
  # subclass of Enumeration, and Rails polymorphic associations store the *base*
  # class name — so the stored type is 'Enumeration', not 'IssuePriority'.
  # Enumeration ids are unique across its subtypes, so this stays unambiguous.
  CONTAINER_TYPES = %w(Issue Project Tracker Enumeration IssueStatus).freeze

  belongs_to :container, :polymorphic => true

  validates :container_id, :presence => true
  validates :container_type, :presence => true, :inclusion => { :in => CONTAINER_TYPES }
  validates :color, :inclusion => { :in => COLORS, :allow_blank => true }
  validates :container_id, :uniqueness => { :scope => :container_type }

  # Resolves a request parameter to a colourable class, or nil.
  def self.container_class(type)
    name = COLORABLE_CLASSES[type.to_s]
    name && name.constantize
  end

  # The value stored in container_type for a given class.
  def self.storage_type(klass)
    klass.base_class.name
  end

  # A deterministic palette entry for a principal, used when colouring by
  # assignee. Picking from the fixed palette rather than deriving a hex value
  # from the login (what RedmineUP does) guarantees the result is readable —
  # a hash-derived colour can land on near-white or near-black.
  def self.for_principal(principal)
    return nil if principal.nil?

    key = principal.id.to_i
    COLORS[key % COLORS.size]
  end

  # Colour by how much of the estimate has been spent.
  def self.for_spent_time(estimated_hours, spent_hours)
    return nil if estimated_hours.blank? || estimated_hours.to_f <= 0

    ratio = spent_hours.to_f / estimated_hours.to_f
    case ratio
    when 0...0.5 then 'green'
    when 0.5...0.8 then 'light_green'
    when 0.8...1.0 then 'yellow'
    when 1.0...1.25 then 'orange'
    else 'red'
    end
  end
end
