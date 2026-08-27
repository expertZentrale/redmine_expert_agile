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
  # Ordered by hue, not by when each colour was added: the picker shows the
  # palette in this order, and related shades sitting together is what makes a
  # colour findable without reading its name.
  #
  # The value is the accent the card's left border carries. It lives here rather
  # than only in the stylesheet so the picker can paint its swatches inline: a
  # swatch that needs a stylesheet to have a colour shows nothing at all on a
  # page that does not load one, which is what the picker did on the two screens
  # it appears on. expert_agile.css still carries the card rules, and a test
  # pins the two to the same values.
  PALETTE = {
    'dark_green'   => '#2f7d55',
    'green'        => '#3c9c3c',
    'light_green'  => '#8dc63f',
    'olive'        => '#7f8c34',
    'turquoise'    => '#29a8a0',
    'light_blue'   => '#3fa5d8',
    'blue'         => '#3d7ec4',
    'indigo'       => '#4257b2',
    'purple'       => '#8a5fbf',
    'light_purple' => '#a98cd9',
    'pink'         => '#d1489b',
    'red'          => '#cc3b3b',
    'salmon'       => '#e0715e',
    'orange'       => '#e08a1e',
    'brown'        => '#9c6b42',
    'yellow'       => '#dcb800',
    'slate'        => '#64748b',
    'gray'         => '#8c8c8c'
  }.freeze

  COLORS = PALETTE.keys.freeze

  # The accent of a palette name, or nil for "no colour".
  def self.hex(color)
    PALETTE[color.to_s]
  end

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

  # A deterministic palette entry for any record with an id — used for
  # assignees, and as the fallback for containers nobody has coloured by hand.
  # Picking from the fixed palette rather than deriving a hex value from the
  # login (what RedmineUP does) guarantees the result is readable: a
  # hash-derived colour can land on near-white or near-black.
  def self.for_principal(record)
    return nil if record.nil? || !record.respond_to?(:id) || record.id.nil?

    COLORS[record.id.to_i % COLORS.size]
  end

  # Priorities get a semantic ramp rather than an arbitrary palette entry:
  # low is calm, urgent is red. Derived from the priority's position in the
  # enumeration, so it adapts to however many levels an instance defines
  # instead of hard-coding Redmine's default five.
  PRIORITY_RAMP = %w(gray blue green yellow orange red).freeze

  def self.for_priority(priority)
    return nil if priority.nil?

    all = IssuePriority.active.to_a
    index = all.index { |candidate| candidate.id == priority.id }
    return for_principal(priority) if index.nil? || all.size < 2

    position = (index.to_f / (all.size - 1) * (PRIORITY_RAMP.size - 1)).round
    PRIORITY_RAMP[position]
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
