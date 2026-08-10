module RedmineExpertAgile
  module Charts
    # Issue counts per status over time. A widening band is a bottleneck.
    class CumulativeFlow < Base
      def data
        statuses = IssueStatus.sorted.to_a
        counts_per_date = dates.map { |date| projection.states_on(date) }

        datasets = statuses.filter_map do |status|
          series = counts_per_date.map do |states|
            states.count { |_id, snapshot| snapshot.status_id == status.id }
          end
          next if series.all?(&:zero?)

          dataset(status.name, series, :actual,
                  :fill => true,
                  :extra => { :backgroundColor => status_color(status), :borderWidth => 1 })
        end

        {
          :title => l(:label_expert_agile_chart_cumulative_flow),
          :y_title => l(:label_expert_agile_chart_unit_issues),
          :type => 'line',
          :stacked => true,
          :labels => labels,
          :datasets => datasets
        }
      end

      private

      # Deterministic hue per status, evenly spaced round the colour wheel.
      def status_color(status)
        index = IssueStatus.sorted.to_a.index(status).to_i
        total = [IssueStatus.count, 1].max
        "hsla(#{(index * 360 / total) % 360}, 55%, 60%, 0.65)"
      end
    end
  end
end
