module RedmineExpertAgile
  module Charts
    # Completed work against the total, which makes scope growth visible in a
    # way a burndown cannot.
    class Burnup < Base
      def data
        completed = dates.map { |date| round(completed_on(date)) }
        total = dates.map { |date| round(total_on(date)) }
        {
          :title => l(:label_expert_agile_chart_burnup),
          :y_title => unit_label,
          :type => 'line',
          :labels => labels,
          :datasets => [
            dataset(l(:label_expert_agile_chart_completed), completed, :actual),
            dataset(l(:label_expert_agile_chart_scope), total, :total)
          ]
        }
      end

      private

      def issue_by_id(id)
        @issue_index ||= issues.index_by(&:id)
        @issue_index[id]
      end

      def completed_on(date)
        projection.closed_on(date).keys.sum { |id| weight_of(issue_by_id(id)) }
      end

      # Scope as it stood on that date — issues created later are not counted.
      def total_on(date)
        projection.states_on(date).keys.sum { |id| weight_of(issue_by_id(id)) }
      end
    end
  end
end
