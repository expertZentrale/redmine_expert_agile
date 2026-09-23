# A card colour, attached polymorphically to whatever the board colours by.
#
# One row per container, enforced by a unique index on
# (container_type, container_id).
class ExpertAgileColor < ExpertAgileApplicationRecord
  self.table_name = 'expert_agile_colors'

  # The colour itself is stored as #rrggbb, so any colour can be picked. This
  # palette is what the picker offers as swatches, and what every fallback draws
  # from — a colour nobody chose should still be one of these, not a hash-derived
  # hex that can land on near-white or near-black.
  #
  # Ordered by hue, not by when each colour was added: the picker shows the
  # swatches in this order, and related shades sitting together is what makes a
  # colour findable at a glance.
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

  SWATCHES = PALETTE.values.freeze

  HEX = /\A#\h{6}\z/.freeze
  SHORT_HEX = /\A#(\h)(\h)(\h)\z/.freeze

  # How much of the colour goes into the background behind a card's text, and
  # behind a swimlane's band. Low on purpose: however dark the pick, the tint
  # stays pale enough for the card's dark text to read. The accent itself only
  # ever colours a border, never the ground text sits on.
  CARD_TINT = 0.07
  LANE_TINT = 0.09

  # A submitted colour as it is stored: lowercase #rrggbb, #rgb expanded, or nil
  # for anything that is not a colour. Leading/trailing blanks are forgiven,
  # anything else is not.
  def self.normalize(value)
    value = value.to_s.strip.downcase
    value = "##{value}" if value =~ /\A\h{3}(\h{3})?\z/
    if (short = value.match(SHORT_HEX))
      value = "##{short[1] * 2}#{short[2] * 2}#{short[3] * 2}"
    end
    value.match?(HEX) ? value : nil
  end

  # The colour mixed into white by `amount`, as #rrggbb.
  def self.tint(hex, amount)
    hex = normalize(hex)
    return nil if hex.nil?

    '#' + hex.delete('#').scan(/../).map { |pair|
      channel = pair.to_i(16)
      format('%02x', (255 - ((255 - channel) * amount)).round)
    }.join
  end

  # The CSS custom properties a coloured element carries, or nil. The rules in
  # expert_agile.css read them, so one rule per element covers every colour.
  def self.css_variables(hex, tint_amount)
    hex = normalize(hex)
    return nil if hex.nil?

    "--ea-accent: #{hex}; --ea-tint: #{tint(hex, tint_amount)};"
  end

  # What the admin screen offers, keyed by the name that appears in the URL.
  # Resolving through this map is what stops `Object.const_get(params[...])`
  # from being reachable at all — RedmineUP does exactly that const_get on user
  # input and relies on a later respond_to? check to limit the damage.
  COLORABLE_CLASSES = {
    'project' => 'Project',
    'tracker' => 'Tracker',
    'issue_priority' => 'IssuePriority',
    'issue_status' => 'IssueStatus'
  }.freeze

  # The values actually stored in container_type. IssuePriority is an STI
  # subclass of Enumeration, and Rails polymorphic associations store the *base*
  # class name — so the stored type is 'Enumeration', not 'IssuePriority'.
  # Enumeration ids are unique across its subtypes, so this stays unambiguous.
  CONTAINER_TYPES = %w(Project Tracker Enumeration IssueStatus).freeze

  belongs_to :container, :polymorphic => true

  validates :container_id, :presence => true
  validates :container_type, :presence => true, :inclusion => { :in => CONTAINER_TYPES }
  validates :color, :format => { :with => HEX, :allow_blank => true }
  validates :container_id, :uniqueness => { :scope => :container_type }

  def color=(value)
    super(value.blank? ? nil : (self.class.normalize(value) || value.to_s))
  end

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
  # Picking from the palette rather than deriving a hex value from the login
  # (what RedmineUP does) guarantees the result is readable: a hash-derived
  # colour can land on near-white or near-black.
  def self.for_principal(record)
    return nil if record.nil? || !record.respond_to?(:id) || record.id.nil?

    SWATCHES[record.id.to_i % SWATCHES.size]
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
    PALETTE[PRIORITY_RAMP[position]]
  end

  # Colour by how much of the estimate has been spent.
  def self.for_spent_time(estimated_hours, spent_hours)
    return nil if estimated_hours.blank? || estimated_hours.to_f <= 0

    ratio = spent_hours.to_f / estimated_hours.to_f
    name =
      case ratio
      when 0...0.5 then 'green'
      when 0.5...0.8 then 'light_green'
      when 0.8...1.0 then 'yellow'
      when 1.0...1.25 then 'orange'
      else 'red'
      end
    PALETTE[name]
  end
end
