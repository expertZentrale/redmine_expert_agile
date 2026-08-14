module RedmineExpertAgile
  module Charts
    # Issue counts per status over time. A widening band is a bottleneck.
    class CumulativeFlow < Base
      def data
        counts_per_date = dates.map { |date| projection.states_on(date) }

        # Collect the bands first: the palette is spread over the statuses this
        # chart actually draws, not over every status in the instance.
        bands = IssueStatus.sorted.to_a.filter_map do |status|
          series = counts_per_date.map do |states|
            states.count { |_id, snapshot| snapshot.status_id == status.id }
          end
          next if series.all?(&:zero?)

          [status, series]
        end

        datasets = bands.each_with_index.map do |(status, series), index|
          dataset(status.name, series, :actual,
                  :fill => true,
                  :extra => { :backgroundColor => status_color(index, bands.size),
                              :borderWidth => 1 })
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

      # Deterministic hue per band, evenly spaced round the colour wheel.
      #
      # Spread over the bands in this chart, not over IssueStatus.count: an
      # installation with fifty statuses would otherwise give a five-band chart
      # five neighbouring hues, and the bands would be indistinguishable.
      def status_color(index, total)
        "hsla(#{(index * 360 / [total, 1].max) % 360}, 55%, 60%, 0.65)"
      end
    end
  end
end
