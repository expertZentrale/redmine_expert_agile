# The backlog planner: an unplanned backlog plus one lane per container.
#
# Parameterised over the container kind rather than duplicated per kind.
# RedmineUP ships AgileSprintsQuery and AgileVersionsQuery, ~10 KB each and
# ~90% identical; everything that actually differs between planning into a
# sprint and planning into a version is isolated in the four small methods at
# the bottom of this class.
class ExpertAgileBacklogQuery < ExpertAgileQuery
  CONTAINER_SPRINT = 'sprint'.freeze
  CONTAINER_VERSION = 'version'.freeze
  CONTAINER_TYPES = [CONTAINER_SPRINT, CONTAINER_VERSION].freeze

  def container_type
    value = options[:container_type].to_s
    CONTAINER_TYPES.include?(value) ? value : CONTAINER_SPRINT
  end

  def container_type=(value)
    options[:container_type] = CONTAINER_TYPES.include?(value.to_s) ? value.to_s : CONTAINER_SPRINT
  end

  def sprints?
    container_type == CONTAINER_SPRINT
  end

  # The lanes to plan into, in planning order.
  def containers
    @containers ||= sprints? ? available_sprints : available_versions
  end

  # Issues already planned into one container, in board rank order.
  def issues_for(container)
    return [] if container.nil?

    planned_scope(container).sorted_by_rank.limit(RedmineExpertAgile.board_items_limit).to_a
  end

  # Everything not planned into any container yet.
  def backlog_issues(term = nil)
    scope = unplanned_scope
    scope = filter_by_term(scope, term) if term.present?
    scope.sorted_by_rank.limit(RedmineExpertAgile.board_items_limit).to_a
  end

  # Aggregates shown in a lane header.
  def totals_for(container)
    scope = container.nil? ? unplanned_scope : planned_scope(container)
    {
      :issue_count => scope.count,
      :estimated_hours => scope.sum(:estimated_hours),
      :story_points => ExpertAgileData.where(:issue_id => scope.select(:id)).sum(:story_points)
    }
  end

  # The scope a planning move ranks within, used when a rebalance is needed.
  def siblings_for(container)
    container.nil? ? unplanned_scope.sorted_by_rank : planned_scope(container).sorted_by_rank
  end

  # Resolves an id from the request to a container this project may plan into.
  # Returning nil for anything else is what keeps a crafted id from moving an
  # issue into a sprint of an unrelated project.
  def container_for(id)
    return nil if id.blank?

    containers.detect { |container| container.id.to_s == id.to_s }
  end

  private

  # The planner ignores the board's status columns: an issue is planned
  # regardless of where it sits in the workflow.
  def planning_scope
    base_scope.eager_load(:status, :tracker, :priority, :assigned_to, :expert_agile_data)
  end

  def filter_by_term(scope, term)
    if term.to_s =~ /\A#?(\d+)\z/
      scope.where(:id => Regexp.last_match(1))
    else
      scope.where("LOWER(#{Issue.table_name}.subject) LIKE ?", "%#{term.to_s.downcase}%")
    end
  end

  # --- The only container-specific parts ------------------------------

  def available_sprints
    project ? project.shared_expert_agile_sprints.available.sorted.to_a : []
  end

  def available_versions
    project ? project.shared_versions.open.sorted.to_a : []
  end

  def planned_scope(container)
    if sprints?
      planning_scope.joins(:expert_agile_data)
                    .where(ExpertAgileData.table_name => { :sprint_id => container.id })
    else
      planning_scope.where(:fixed_version_id => container.id)
    end
  end

  def unplanned_scope
    if sprints?
      planning_scope.where(
        "#{Issue.table_name}.id NOT IN (SELECT issue_id FROM #{ExpertAgileData.table_name} " \
        'WHERE sprint_id IS NOT NULL)'
      )
    else
      planning_scope.where(:fixed_version_id => nil)
    end
  end
end
