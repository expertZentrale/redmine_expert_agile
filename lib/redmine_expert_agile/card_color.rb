# Resolves the colour of one card, given the board's colour basis.
#
# Kept separate from the models so the board can colour a whole page of cards
# without each model knowing about board settings.
module RedmineExpertAgile
  class CardColor
    class << self
      # Returns a palette name (see ExpertAgileColor::COLORS) or nil.
      def for(issue, base)
        return nil if issue.nil?

        case base.to_s
        when 'tracker'    then colour_of(issue.tracker)
        when 'priority'   then colour_of(issue.priority)
        when 'status'     then colour_of(issue.status)
        when 'project'    then colour_of(issue.project)
        when 'issue'      then colour_of(issue)
        when 'assignee'   then ExpertAgileColor.for_principal(issue.assigned_to)
        when 'spent_time' then ExpertAgileColor.for_spent_time(issue.estimated_hours, issue.spent_hours)
        end
      end

      # Preloads the colours for a whole board in one query per container type,
      # so rendering N cards does not issue N lookups.
      def preload(issues, base)
        containers =
          case base.to_s
          when 'tracker'  then issues.map(&:tracker)
          when 'priority' then issues.map(&:priority)
          when 'status'   then issues.map(&:status)
          when 'project'  then issues.map(&:project)
          when 'issue'    then issues
          else return {}
          end

        containers = containers.compact.uniq
        return {} if containers.empty?

        type = containers.first.class.base_class.name
        ExpertAgileColor.where(:container_type => type, :container_id => containers.map(&:id))
                        .pluck(:container_id, :color)
                        .to_h
      end

      private

      def colour_of(container)
        return nil if container.nil?
        return nil unless container.respond_to?(:expert_agile_color)

        record = container.expert_agile_color
        record && record.color.presence
      end
    end
  end
end
