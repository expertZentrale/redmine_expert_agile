module RedmineExpertAgile
  module Charts
    # Remaining work over time, with an ideal line for reference.
    class Burndown < Base
      def data
        remaining = dates.map { |date| round(remaining_on(date)) }
        {
          :title => l(:label_expert_agile_chart_burndown),
          :y_title => unit_label,
          :type => 'line',
          :labels => labels,
          :datasets => [
            dataset(l(:label_expert_agile_chart_remaining), remaining, :actual),
            dataset(l(:label_expert_agile_chart_ideal), ideal_line, :ideal, :dashed => true)
          ]
        }
      end

      private

      # Work still open at the end of each day.
      def remaining_on(date)
        projection.open_on(date).keys.sum { |id| weight_of(issue_by_id(id)) }
      end

      def issue_by_id(id)
        @issue_index ||= issues.index_by(&:id)
        @issue_index[id]
      end

      # Straight line from the starting total to zero. With weekends excluded
      # it only descends on working days, so the reference matches how the team
      # actually works.
      def ideal_line
        start_total = remaining_on(dates.first)
        steps = RedmineExpertAgile.exclude_weekends? ? dates.count { |d| !weekend?(d) } : dates.size
        steps = 1 if steps <= 1
        decrement = start_total.to_f / (steps - 1)

        burned = 0.0
        dates.map do |date|
          value = round([start_total - burned, 0].max)
          burned += decrement unless RedmineExpertAgile.exclude_weekends? && weekend?(date)
          value
        end
      end
    end
  end
end
