# A saved chart: the same issue filters as a board, plus the chart selection
# and an explicit date range.
class ExpertAgileChartsQuery < ExpertAgileQuery
  self.view_permission = :view_expert_agile_charts

  scope :only_charts, -> { where(:type => name) }

  def chart
    value = options[:chart].to_s
    RedmineExpertAgile::Charts::Registry.valid?(value) ? value : RedmineExpertAgile.default_chart
  end

  def chart=(value)
    options[:chart] = RedmineExpertAgile::Charts::Registry.valid?(value) ? value.to_s : nil
  end

  def chart_unit
    value = options[:chart_unit].to_s
    RedmineExpertAgile::Charts::Base::UNITS.include?(value) ? value : 'issues'
  end

  def chart_unit=(value)
    options[:chart_unit] = value.to_s
  end

  def interval
    value = options[:interval].to_s
    RedmineExpertAgile::Charts::Base::INTERVALS.include?(value) ? value : 'day'
  end

  def interval=(value)
    options[:interval] = value.to_s
  end

  # The date range is stored as two explicit values.
  #
  # RedmineUP recovers it by regex-scraping the *generated SQL* of a synthetic
  # filter for `\d{4}-\d{2}-\d{2}` — so any change to Redmine's sql_for_field
  # output silently breaks every chart. There is no reason for the range to be
  # anything other than what it is: two dates.
  def date_from
    parse_date(options[:date_from]) || default_date_from
  end

  def date_from=(value)
    options[:date_from] = value.presence && value.to_s
  end

  def date_to
    parse_date(options[:date_to]) || User.current.today
  end

  def date_to=(value)
    options[:date_to] = value.presence && value.to_s
  end

  # Issues the chart is computed over. Charts ignore the board's status columns
  # — a burndown counts everything the filters select, closed or not.
  def chart_scope
    base_scope.eager_load(:status, :expert_agile_data)
  end

  # Whether this chart would exceed the item cap. Only the journal-replaying
  # charts are bounded; the counting ones are cheap at any size.
  #
  # RedmineUP's equivalent guard tests chart keys ('work_burndown',
  # 'hours_velocity') that no longer exist in their registry, so the cap it
  # advertises never actually fires.
  def too_many_items?
    return false unless RedmineExpertAgile::Charts::Registry.replays_history?(chart)

    chart_scope.count > RedmineExpertAgile.chart_items_limit
  end

  def build_chart
    klass = RedmineExpertAgile::Charts::Registry.chart_class(chart)
    return nil if klass.nil?

    klass.new(chart_scope.to_a,
              :date_from => date_from, :date_to => date_to,
              :unit => chart_unit, :interval => interval)
  end

  # Past chart data cannot change, so it is worth caching. The fingerprint
  # covers everything that could alter the result.
  def cache_key
    scope = chart_scope
    [
      'expert_agile_chart', chart, chart_unit, interval,
      date_from.to_s, date_to.to_s,
      scope.count,
      scope.maximum(:updated_on).to_i,
      project_id, id
    ].join('/')
  end

  private

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def default_date_from
    date_to - 29
  end
end
