module RedmineExpertAgile
  module Charts
    # Created against closed per interval.
    #
    # Counts only — this one needs no journal replay, so it is not subject to
    # the chart item cap.
    class Velocity < Base
      def self.replays_history?
        false
      end

      def self.chart_type
        'bar'
      end

      def data
        created = bucket(issues.map { |issue| issue.created_on&.to_date })
        closed = bucket(issues.map { |issue| issue.closed_on&.to_date })
        {
          :title => l(:label_expert_agile_chart_velocity),
          :y_title => l(:label_expert_agile_chart_unit_issues),
          :type => 'bar',
          :labels => labels,
          :datasets => [
            dataset(l(:field_created_on), created, :created),
            dataset(l(:label_expert_agile_chart_closed), closed, :closed)
          ]
        }
      end

      private

      # Each date falls into the interval bucket that starts on or before it.
      def bucket(values)
        counts = Array.new(dates.size, 0)
        values.compact.each do |date|
          index = bucket_index(date)
          counts[index] += 1 if index
        end
        counts
      end

      def bucket_index(date)
        return nil if date < dates.first || date > date_to

        found = nil
        dates.each_with_index { |start, index| found = index if start <= date }
        found
      end
    end
  end
end
