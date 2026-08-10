require File.expand_path('../../test_helper', __FILE__)

# The chart classes, against hand-built histories with values worked out by
# hand — a chart that renders is not the same as a chart that is right.
class ExpertAgileChartsTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles,
           :enabled_modules, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :issues

  Charts = RedmineExpertAgile::Charts

  def setup
    @project = Project.find(1)
    @project.enable_module!(:expert_agile)
    User.current = User.find(1)
    @open_status = IssueStatus.where(:is_closed => false).first
    @closed_status = IssueStatus.where(:is_closed => true).first
    @from = Date.new(2026, 1, 1)
    @to = Date.new(2026, 1, 5)
  end

  def teardown
    User.current = nil
    ExpertAgileData.delete_all
  end

  def at(date)
    Time.utc(date.year, date.month, date.day, 12, 0, 0)
  end

  def issue_on(date, options = {})
    issue = Issue.generate!({ :project_id => @project.id, :status_id => @open_status.id,
                              :done_ratio => 0 }.merge(options))
    issue.update_columns(:created_on => at(date), :updated_on => at(date))
    issue.reload
  end

  def close!(issue, date)
    journal = Journal.create!(:journalized => issue, :user => User.current)
    journal.update_columns(:created_on => at(date))
    JournalDetail.create!(:journal_id => journal.id, :property => 'attr', :prop_key => 'status_id',
                          :old_value => @open_status.id.to_s, :value => @closed_status.id.to_s)
    issue.update_columns(:status_id => @closed_status.id, :closed_on => at(date))
    issue.reload
  end

  def chart_options(extra = {})
    { :date_from => @from, :date_to => @to }.merge(extra)
  end

  # --- Burndown ---------------------------------------------------------

  def test_burndown_counts_open_issues_per_day
    a = issue_on(@from)
    issue_on(@from)
    close!(a, Date.new(2026, 1, 3))

    data = Charts::Burndown.new([a.reload, Issue.find(Issue.maximum(:id))], chart_options).data
    remaining = data[:datasets].first[:data]

    assert_equal 5, data[:labels].size, 'one label per day, inclusive'
    assert_equal [2.0, 2.0, 1.0, 1.0, 1.0], remaining
  end

  def test_burndown_in_story_points_weights_by_points
    a = issue_on(@from)
    b = issue_on(@from)
    ExpertAgileData.create!(:issue_id => a.id, :story_points => 5)
    ExpertAgileData.create!(:issue_id => b.id, :story_points => 3)
    close!(a, Date.new(2026, 1, 3))

    data = Charts::Burndown.new([a.reload, b.reload],
                                chart_options(:unit => 'story_points')).data

    assert_equal [8.0, 8.0, 3.0, 3.0, 3.0], data[:datasets].first[:data]
  end

  def test_burndown_ideal_line_starts_at_the_total_and_ends_at_zero
    issue_on(@from)
    issues = [Issue.find(Issue.maximum(:id))]

    ideal = Charts::Burndown.new(issues, chart_options).data[:datasets].last[:data]

    assert_equal 1.0, ideal.first
    assert_equal 0.0, ideal.last
    assert_equal ideal.sort.reverse, ideal, 'the ideal line only descends'
  end

  # --- Burnup -----------------------------------------------------------

  def test_burnup_tracks_completed_against_scope
    a = issue_on(@from)
    b = issue_on(Date.new(2026, 1, 3))
    close!(a, Date.new(2026, 1, 4))

    data = Charts::Burnup.new([a.reload, b.reload], chart_options).data
    completed = data[:datasets].first[:data]
    scope = data[:datasets].last[:data]

    assert_equal [0.0, 0.0, 0.0, 1.0, 1.0], completed
    # Scope grows on the 3rd, when the second issue is created — which is the
    # thing a burndown cannot show.
    assert_equal [1.0, 1.0, 2.0, 2.0, 2.0], scope
  end

  # --- Cumulative flow ---------------------------------------------------

  def test_cumulative_flow_counts_per_status
    a = issue_on(@from)
    close!(a, Date.new(2026, 1, 4))

    data = Charts::CumulativeFlow.new([a.reload], chart_options).data
    series = data[:datasets].map { |set| [set[:label], set[:data]] }.to_h

    assert data[:stacked], 'a cumulative flow diagram is stacked'
    assert_equal [1, 1, 1, 0, 0], series[@open_status.name]
    assert_equal [0, 0, 0, 1, 1], series[@closed_status.name]
  end

  def test_cumulative_flow_omits_statuses_that_are_never_used
    issue_on(@from)
    data = Charts::CumulativeFlow.new([Issue.find(Issue.maximum(:id))], chart_options).data

    assert_equal [@open_status.name], data[:datasets].map { |set| set[:label] }
  end

  # --- Velocity ----------------------------------------------------------

  def test_velocity_buckets_created_and_closed
    a = issue_on(@from)
    close!(a, Date.new(2026, 1, 3))
    b = issue_on(Date.new(2026, 1, 2))

    data = Charts::Velocity.new([a.reload, b.reload], chart_options).data
    created = data[:datasets].first[:data]
    closed = data[:datasets].last[:data]

    assert_equal [1, 1, 0, 0, 0], created
    assert_equal [0, 0, 1, 0, 0], closed
  end

  def test_velocity_does_not_replay_history
    # Counting charts work off created_on/closed_on, so they are not subject to
    # the item cap.
    assert_not Charts::Velocity.replays_history?
    assert_not Charts::CycleTime.replays_history?
    assert Charts::Burndown.replays_history?
    assert Charts::CumulativeFlow.replays_history?
  end

  # --- Cycle time --------------------------------------------------------

  def test_cycle_time_measures_creation_to_closure
    a = issue_on(@from)
    close!(a, Date.new(2026, 1, 4))

    data = Charts::CycleTime.new([a.reload], chart_options).data

    assert_equal [3.0], data[:datasets].first[:data]
    assert_equal 3.0, data[:average]
  end

  def test_cycle_time_ignores_open_issues
    issue_on(@from)

    data = Charts::CycleTime.new([Issue.find(Issue.maximum(:id))], chart_options).data

    assert_equal [], data[:datasets].first[:data]
    assert_equal 0, data[:average]
  end

  # --- Registry ----------------------------------------------------------

  def test_registry_resolves_only_known_charts
    assert_equal Charts::Burndown, Charts::Registry.chart_class('burndown')
    assert_nil Charts::Registry.chart_class('Kernel')
    assert_nil Charts::Registry.chart_class('nonsense')
    assert_not Charts::Registry.valid?('nonsense')
  end

  def test_every_registered_chart_produces_a_drawable_payload
    Charts::Registry.names.each do |name|
      chart = Charts::Registry.chart_class(name).new([issue_on(@from)], chart_options)
      data = chart.data

      assert data[:labels].is_a?(Array), "#{name} has no labels"
      assert data[:datasets].is_a?(Array), "#{name} has no datasets"
      data[:datasets].each do |set|
        assert set[:data].is_a?(Array), "#{name} dataset #{set[:label]} has no data"
        assert_match(/rgba?\(|hsla?\(/, set[:backgroundColor].to_s,
                     "#{name} must use a fixed colour, never a random one")
      end
    end
  end

  # --- Query -------------------------------------------------------------

  def test_chart_query_stores_the_date_range_explicitly
    # Not recovered by regex-scraping generated SQL, which is how the RedmineUP
    # equivalent does it and why any change to Redmine's sql_for_field breaks
    # every chart there.
    query = ExpertAgileChartsQuery.new(:name => '_', :project => @project)
    query.date_from = '2026-01-01'
    query.date_to = '2026-01-31'
    query.save!

    reloaded = ExpertAgileChartsQuery.find(query.id)
    assert_equal Date.new(2026, 1, 1), reloaded.date_from
    assert_equal Date.new(2026, 1, 31), reloaded.date_to
  end

  def test_chart_query_falls_back_for_invalid_input
    query = ExpertAgileChartsQuery.new(:name => '_', :project => @project)
    query.date_from = 'not a date'
    query.chart = 'nonsense'

    assert_equal query.date_to - 29, query.date_from
    assert_equal RedmineExpertAgile.default_chart, query.chart
  end

  def test_item_cap_applies_only_to_history_replaying_charts
    query = ExpertAgileChartsQuery.new(:name => '_', :project => @project)
    issue_on(@from)

    with_agile_settings('chart_items_limit' => '0') do
      query.chart = 'burndown'
      assert query.too_many_items?, 'a replaying chart is capped'

      query.chart = 'velocity'
      assert_not query.too_many_items?, 'a counting chart is not capped'
    end
  end

  def test_cache_key_changes_when_the_scope_changes
    query = ExpertAgileChartsQuery.new(:name => '_', :project => @project)
    query.chart = 'burndown'
    before = query.cache_key

    issue_on(@from)

    assert_not_equal before, ExpertAgileChartsQuery.new(:name => '_', :project => @project)
                                                   .tap { |q| q.chart = 'burndown' }.cache_key
  end
end
