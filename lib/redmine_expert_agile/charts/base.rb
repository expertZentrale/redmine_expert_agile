module RedmineExpertAgile
  module Charts
    # Common shape for every chart: a date axis, a unit, and a Chart.js-ready
    # payload.
    #
    # Colours are fixed per series. RedmineUP falls back to
    # [rand(255), rand(255), rand(255)] when no colour is given, so a chart
    # changes colour on every reload.
    class Base
      UNIT_ISSUES = 'issues'.freeze
      UNIT_HOURS = 'hours'.freeze
      UNIT_STORY_POINTS = 'story_points'.freeze
      UNITS = [UNIT_ISSUES, UNIT_HOURS, UNIT_STORY_POINTS].freeze

      INTERVALS = %w(day week month).freeze

      # Series that report what actually happened. Everything here is cut off at
      # today unless the instance opts into future data; :ideal is a projection
      # and is drawn across the whole range either way.
      MEASURED_SERIES = %i(actual total created closed trend).freeze

      PALETTE = {
        :actual => '54, 126, 196',
        :ideal => '140, 140, 140',
        :total => '60, 156, 60',
        :created => '224, 138, 30',
        :closed => '60, 156, 60',
        :trend => '138, 95, 191'
      }.freeze

      attr_reader :issues, :date_from, :date_to, :unit, :interval

      def initialize(issues, options = {})
        @issues = Array(issues)
        @date_from = options[:date_from]
        @date_to = options[:date_to]
        @unit = UNITS.include?(options[:unit].to_s) ? options[:unit].to_s : UNIT_ISSUES
        @interval = INTERVALS.include?(options[:interval].to_s) ? options[:interval].to_s : 'day'
        @projection = nil
      end

      # Subclasses implement this and return {:labels, :datasets, ...}.
      def data
        raise NotImplementedError
      end

      # Whether this chart has to replay history, and so is subject to the item
      # cap. Counting charts work off created_on/closed_on aggregates and are
      # cheap regardless of scope size.
      def self.replays_history?
        true
      end

      def self.chart_type
        'line'
      end

      # Whether a series index maps onto `dates`, i.e. whether the chart's x
      # axis is the date axis. Cycle time is the exception: it plots one point
      # per closed issue, so index 3 there is an issue, not the fourth bucket,
      # and truncating it against the date axis would drop real measurements.
      def self.date_aligned?
        true
      end

      protected

      def projection
        @projection ||= RedmineExpertAgile::JournalProjection.new(issues)
      end

      # The dates on the x axis, one per interval step.
      def dates
        @dates ||= begin
          from = date_from
          to = date_to
          result = []
          cursor = from
          while cursor <= to
            result << cursor
            cursor = advance(cursor)
          end
          result << to if result.last != to
          result
        end
      end

      def advance(date)
        case interval
        when 'week' then date + 7
        when 'month' then date >> 1
        else date + 1
        end
      end

      def labels
        dates.map { |date| format_label(date) }
      end

      def format_label(date)
        case interval
        when 'month' then date.strftime('%Y-%m')
        else date.strftime('%Y-%m-%d')
        end
      end

      def weekend?(date)
        [0, 6].include?(date.wday)
      end

      # How much one issue contributes, in the selected unit.
      def weight_of(issue)
        case unit
        when UNIT_HOURS then issue.estimated_hours.to_f
        when UNIT_STORY_POINTS then issue.story_points.to_f
        else 1.0
        end
      end

      def total_weight
        @total_weight ||= issues.sum { |issue| weight_of(issue) }
      end

      def unit_label
        case unit
        when UNIT_HOURS then l(:label_expert_agile_chart_unit_hours)
        when UNIT_STORY_POINTS then l(:label_expert_agile_chart_unit_story_points)
        else l(:label_expert_agile_chart_unit_issues)
        end
      end

      def l(*args)
        ::I18n.t(*args)
      end

      def dataset(label, values, color_key, options = {})
        rgb = PALETTE[color_key] || PALETTE[:actual]
        values = truncate_future(values) if MEASURED_SERIES.include?(color_key)
        {
          :label => label,
          :data => values,
          :borderColor => "rgba(#{rgb}, 1)",
          :backgroundColor => "rgba(#{rgb}, #{options[:fill] ? 0.2 : 1})",
          :fill => options.fetch(:fill, false),
          :borderDash => options[:dashed] ? [6, 4] : [],
          :borderWidth => 2,
          :pointRadius => options.fetch(:point_radius, 0),
          :tension => 0.1
        }.merge(options[:extra] || {})
      end

      # Nils out the buckets that start after today, so a series that measures
      # what happened stops at today instead of running flat to the end of the
      # range. Chart.js skips nil points, so the ideal line — a projection, and
      # deliberately not in MEASURED_SERIES — still spans the whole sprint.
      #
      # A bucket that merely *contains* today is kept: a week or month interval
      # is legitimately partial on the day you look at it.
      def truncate_future(values)
        return values unless self.class.date_aligned?
        return values if RedmineExpertAgile.chart_future_data?

        today = User.current.today
        values.each_with_index.map do |value, index|
          date = dates[index]
          date && date > today ? nil : value
        end
      end

      def round(value)
        value.to_f.round(2)
      end
    end
  end
end
