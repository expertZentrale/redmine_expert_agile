module RedmineExpertAgile
  module Charts
    # The available charts, keyed by the name that appears in URLs and in a
    # saved chart query.
    module Registry
      CHARTS = {
        'burndown' => { :class_name => 'RedmineExpertAgile::Charts::Burndown',
                        :label => :label_expert_agile_chart_burndown, :units => true },
        'burnup' => { :class_name => 'RedmineExpertAgile::Charts::Burnup',
                      :label => :label_expert_agile_chart_burnup, :units => true },
        'cumulative_flow' => { :class_name => 'RedmineExpertAgile::Charts::CumulativeFlow',
                               :label => :label_expert_agile_chart_cumulative_flow, :units => false },
        'velocity' => { :class_name => 'RedmineExpertAgile::Charts::Velocity',
                        :label => :label_expert_agile_chart_velocity, :units => false },
        'cycle_time' => { :class_name => 'RedmineExpertAgile::Charts::CycleTime',
                          :label => :label_expert_agile_chart_cycle_time, :units => false }
      }.freeze

      module_function

      def names
        CHARTS.keys
      end

      def valid?(name)
        CHARTS.key?(name.to_s)
      end

      # Resolved through the registry, never constantized from a parameter.
      def chart_class(name)
        entry = CHARTS[name.to_s]
        entry && entry[:class_name].constantize
      end

      def label(name)
        entry = CHARTS[name.to_s]
        entry && entry[:label]
      end

      def units?(name)
        entry = CHARTS[name.to_s]
        entry ? entry[:units] : false
      end

      # Only charts that replay journals are bounded by the item cap; the
      # counting charts are cheap at any scope.
      def replays_history?(name)
        klass = chart_class(name)
        klass ? klass.replays_history? : false
      end
    end
  end
end
