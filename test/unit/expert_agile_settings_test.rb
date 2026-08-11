require File.expand_path('../../test_helper', __FILE__)

# Covers the typed settings readers in lib/redmine_expert_agile.rb.
#
# The point of these is that every default lives in init.rb and the readers only
# cast, so the stored settings hash and the effective configuration can never
# disagree. The tests pin both halves of that: the declared defaults are what
# the readers return, and explicit values override them correctly.
class ExpertAgileSettingsTest < ActiveSupport::TestCase
  def test_plugin_is_registered
    plugin = Redmine::Plugin.find(:redmine_expert_agile)

    assert_equal 'Redmine expert Agile', plugin.name
    assert_match(/\A\d+\.\d+\.\d+/, plugin.version)
  end

  def test_every_declared_default_is_readable
    defaults = Redmine::Plugin.find(:redmine_expert_agile).settings[:default]

    assert defaults.any?, 'plugin declares no default settings'
    defaults.each_key do |key|
      assert_not_nil RedmineExpertAgile.setting(key),
                     "setting #{key} has no effective value"
    end
  end

  def test_settings_added_later_still_read_their_declared_default
    # Redmine hands back the stored hash wholesale once the settings form has
    # been saved once, so a key introduced in a later version is absent on an
    # existing installation. Without merging the declared defaults underneath,
    # a numeric setting reads as nil -> 0, which is how the description excerpt
    # length collapsed to its floor on a real instance.
    Setting.plugin_redmine_expert_agile = { 'color_base' => 'status' }

    assert_equal 140, RedmineExpertAgile.card_description_length
    assert_equal 500, RedmineExpertAgile.board_items_limit
    assert_equal 'status', RedmineExpertAgile.color_base, 'a stored value still wins'
  ensure
    Setting.plugin_redmine_expert_agile = {}
  end

  def test_a_stored_blank_value_is_not_overwritten_by_the_default
    # "no trackers selected" is a real choice and must not be replaced by the
    # default just because it is empty.
    Setting.plugin_redmine_expert_agile = { 'sp_values' => '' }

    assert_equal [], RedmineExpertAgile.sp_values
  ensure
    Setting.plugin_redmine_expert_agile = {}
  end

  def test_boolean_settings_read_as_booleans
    with_agile_settings('story_points_on' => '1') do
      assert RedmineExpertAgile.use_story_points?
    end

    with_agile_settings('story_points_on' => '0') do
      assert_not RedmineExpertAgile.use_story_points?
    end
  end

  def test_setting_list_accepts_comma_string_and_array
    with_agile_settings('sp_values' => '0,1, 2 ,3,,5') do
      assert_equal [0, 1, 2, 3, 5], RedmineExpertAgile.sp_values
    end

    # A multi-select posts a real Array, and Redmine stores it as one.
    with_agile_settings('trackers_for_sp' => ['', '2', '1']) do
      assert_equal [2, 1], RedmineExpertAgile.trackers_for_sp
    end
  end

  def test_color_base_falls_back_for_unknown_value
    with_agile_settings('color_base' => 'not_a_base') do
      assert_equal 'none', RedmineExpertAgile.color_base
      assert_not RedmineExpertAgile.use_colors?
    end

    with_agile_settings('color_base' => 'tracker') do
      assert_equal 'tracker', RedmineExpertAgile.color_base
      assert RedmineExpertAgile.use_colors?
    end
  end

  def test_estimate_units_falls_back_for_unknown_value
    with_agile_settings('estimate_units' => 'bananas') do
      assert_equal 'hours', RedmineExpertAgile.estimate_units
    end
  end

  def test_story_points_for_tracker_honours_tracker_restriction
    tracker = Tracker.first

    with_agile_settings('story_points_on' => '0', 'trackers_for_sp' => '') do
      assert_not RedmineExpertAgile.story_points_for_tracker?(tracker)
    end

    # Empty restriction means "every tracker".
    with_agile_settings('story_points_on' => '1', 'trackers_for_sp' => '') do
      assert RedmineExpertAgile.story_points_for_tracker?(tracker)
    end

    with_agile_settings('story_points_on' => '1', 'trackers_for_sp' => tracker.id.to_s) do
      assert RedmineExpertAgile.story_points_for_tracker?(tracker)
    end

    with_agile_settings('story_points_on' => '1', 'trackers_for_sp' => (tracker.id + 1000).to_s) do
      assert_not RedmineExpertAgile.story_points_for_tracker?(tracker)
    end
  end

  def test_numeric_limits_never_drop_below_one
    with_agile_settings('board_items_limit' => '0', 'chart_items_limit' => '-5') do
      assert_equal 1, RedmineExpertAgile.board_items_limit
      assert_equal 1, RedmineExpertAgile.chart_items_limit
    end
  end

  def test_chart_cache_can_be_disabled
    with_agile_settings('chart_cache_minutes' => '0') do
      assert_not RedmineExpertAgile.chart_cache?
    end

    with_agile_settings('chart_cache_minutes' => '15') do
      assert RedmineExpertAgile.chart_cache?
      assert_equal 15, RedmineExpertAgile.chart_cache_minutes
    end
  end

  def test_project_modules_and_permissions_are_registered
    assert_includes Redmine::AccessControl.available_project_modules, :expert_agile
    assert_includes Redmine::AccessControl.available_project_modules, :expert_agile_backlog

    %i(view_expert_agile_board edit_expert_agile_board view_expert_agile_charts
       manage_expert_agile_sprints view_expert_agile_backlog manage_expert_agile_backlog).each do |name|
      assert_not_nil Redmine::AccessControl.permission(name), "permission #{name} is not registered"
    end
  end
end
