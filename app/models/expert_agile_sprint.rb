# A sprint: a named, dated container for issues, independent of Redmine
# versions.
#
# Versions carry release semantics and have no start date, so a sprint burndown
# would need one stored somewhere anyway. Sprints and versions coexist — the
# backlog planner can plan into either.
class ExpertAgileSprint < ExpertAgileApplicationRecord
  include Redmine::SafeAttributes

  self.table_name = 'expert_agile_sprints'

  STATUS_OPEN = 0
  STATUS_ACTIVE = 1
  STATUS_CLOSED = 2
  STATUSES = { STATUS_OPEN => 'open', STATUS_ACTIVE => 'active', STATUS_CLOSED => 'closed' }.freeze

  # Mirrors Version#sharing semantics so a sprint can span a project tree the
  # same way a shared version does.
  SHARING_NONE = 0
  SHARING_DESCENDANTS = 1
  SHARING_HIERARCHY = 2
  SHARING_TREE = 3
  SHARING_SYSTEM = 4
  SHARINGS = {
    SHARING_NONE => 'none', SHARING_DESCENDANTS => 'descendants',
    SHARING_HIERARCHY => 'hierarchy', SHARING_TREE => 'tree', SHARING_SYSTEM => 'system'
  }.freeze

  belongs_to :project
  has_many :expert_agile_data, :class_name => 'ExpertAgileData', :foreign_key => 'sprint_id',
                               :dependent => :nullify
  has_many :issues, :through => :expert_agile_data, :source => :issue

  validates :project_id, :name, :start_date, :end_date, :presence => true
  validates :status, :inclusion => { :in => STATUSES.keys }
  validates :sharing, :inclusion => { :in => SHARINGS.keys }
  validates :name, :uniqueness => { :scope => :project_id, :case_sensitive => false }
  validate :end_date_after_start_date
  validate :no_overlapping_sprint
  validate :no_open_issues_when_closing

  before_save :deactivate_sibling_sprints, :if => :becoming_active?

  scope :open, -> { where(:status => STATUS_OPEN) }
  scope :active, -> { where(:status => STATUS_ACTIVE) }
  scope :closed, -> { where(:status => STATUS_CLOSED) }
  scope :available, -> { where(:status => [STATUS_OPEN, STATUS_ACTIVE]) }
  scope :for_project, ->(project) { where(:project_id => project) }
  # Sorted the way a planner reads them: active first, then open, then closed,
  # newest start date first within each.
  scope :sorted, -> { order(Arel.sql('CASE status WHEN 1 THEN 0 WHEN 0 THEN 1 ELSE 2 END')).order(:start_date => :desc) }
  scope :visible, lambda { |user = User.current|
    joins(:project).where(Project.allowed_to_condition(user, :view_expert_agile_board))
  }

  safe_attributes 'name', 'description', 'start_date', 'end_date', 'status', 'sharing'

  def status_name
    STATUSES[status]
  end

  def sharing_name
    SHARINGS[sharing]
  end

  def open?
    status == STATUS_OPEN
  end

  def active?
    status == STATUS_ACTIVE
  end

  def closed?
    status == STATUS_CLOSED
  end

  def to_s
    name.to_s
  end

  # Length in days, inclusive of both end dates.
  def length
    return nil if start_date.blank? || end_date.blank?

    (end_date - start_date).to_i + 1
  end

  # Whole days left, floored at zero.
  def remaining_days(today = User.current.today)
    return nil if end_date.blank?

    [(end_date - today).to_i, 0].max
  end

  # The projects that may use this sprint.
  #
  # Expressed as nested-set ranges through ActiveRecord rather than by
  # interpolating lft/rgt into a SQL string, which is how the RedmineUP
  # equivalent is written.
  def shared_projects
    return Project.where(:id => project_id) if project.nil? || sharing == SHARING_NONE

    case sharing
    when SHARING_SYSTEM
      Project.all
    when SHARING_TREE
      # Redmine's Project is an awesome_nested_set with lft/rgt and no root_id
      # column, so "same tree" is expressed as the root's nested-set span.
      root = project.root
      Project.where('projects.lft >= :lft AND projects.rgt <= :rgt',
                    :lft => root.lft, :rgt => root.rgt)
    when SHARING_HIERARCHY
      # Ancestors or descendants: the vertical line through this project.
      Project.where('(projects.lft <= :lft AND projects.rgt >= :rgt) OR ' \
                    '(projects.lft >= :lft AND projects.rgt <= :rgt)',
                    :lft => project.lft, :rgt => project.rgt)
    when SHARING_DESCENDANTS
      Project.where('projects.lft >= :lft AND projects.rgt <= :rgt',
                    :lft => project.lft, :rgt => project.rgt)
    else
      Project.where(:id => project_id)
    end
  end

  def shared_with?(other_project)
    return false if other_project.nil?

    shared_projects.where(:id => other_project.id).exists?
  end

  private

  def becoming_active?
    status == STATUS_ACTIVE && (new_record? || status_changed?)
  end

  # A project runs one active sprint at a time; activating one stands the
  # others down.
  def deactivate_sibling_sprints
    scope = self.class.where(:project_id => project_id, :status => STATUS_ACTIVE)
    scope = scope.where.not(:id => id) if persisted?
    scope.update_all(:status => STATUS_OPEN)
  end

  def end_date_after_start_date
    return if start_date.blank? || end_date.blank?
    return if end_date >= start_date

    errors.add(:end_date, :invalid, :message => l(:error_expert_agile_sprint_dates_order))
  end

  def no_overlapping_sprint
    return if start_date.blank? || end_date.blank? || project_id.blank?
    return if RedmineExpertAgile.allow_overlapping_sprints?
    # A shared sprint deliberately spans other projects' timelines, so overlap
    # only means something for sprints kept inside one project.
    return unless sharing == SHARING_NONE

    scope = self.class.where(:project_id => project_id, :sharing => SHARING_NONE)
                      .where('start_date <= :end AND end_date >= :start',
                             :start => start_date, :end => end_date)
    scope = scope.where.not(:id => id) if persisted?
    return unless scope.exists?

    errors.add(:base, l(:error_expert_agile_sprint_dates_overlap))
  end

  def no_open_issues_when_closing
    return unless status == STATUS_CLOSED
    return if new_record?
    return unless status_changed?
    return unless issues.open.exists?

    errors.add(:base, l(:error_expert_agile_sprint_has_open_issues))
  end
end
