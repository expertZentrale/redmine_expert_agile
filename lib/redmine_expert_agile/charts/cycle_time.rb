module RedmineExpertAgile
  module Charts
    # Days from creation to closure for each closed issue, with a moving
    # average. Counts only, so no journal replay.
    class CycleTime < Base
      WINDOW = 5

      def self.replays_history?
        false
      end

      def self.chart_type
        'line'
      end

      def data
        points = closed_issues.map do |issue|
          { :date => issue.closed_on.to_date, :days => cycle_days(issue), :id => issue.id }
        end.sort_by { |point| point[:date] }

        {
          :title => l(:label_expert_agile_chart_cycle_time),
          :y_title => l(:label_expert_agile_chart_days),
          :type => 'line',
          :labels => points.map { |point| point[:date].strftime('%Y-%m-%d') },
          :datasets => [
            dataset(l(:label_expert_agile_chart_cycle_time), points.map { |p| round(p[:days]) },
                    :actual, :point_radius => 3, :extra => { :showLine => false }),
            dataset(l(:label_expert_agile_chart_moving_average),
                    moving_average(points.map { |p| p[:days] }), :trend, :dashed => true)
          ],
          :average => points.any? ? round(points.sum { |p| p[:days] } / points.size.to_f) : 0
        }
      end

      private

      def closed_issues
        issues.select do |issue|
          issue.closed_on.present? && issue.created_on.present? &&
            issue.closed_on.to_date >= date_from && issue.closed_on.to_date <= date_to
        end
      end

      def cycle_days(issue)
        [(issue.closed_on - issue.created_on) / 86_400.0, 0].max
      end

      def moving_average(values)
        values.each_with_index.map do |_value, index|
          window = values[[0, index - WINDOW + 1].max..index]
          round(window.sum / window.size.to_f)
        end
      end
    end
  end
end
