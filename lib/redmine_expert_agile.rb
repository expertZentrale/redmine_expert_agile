# Central namespace and typed access to the plugin settings.
#
# Redmine merges the defaults declared in init.rb into
# Setting.plugin_redmine_expert_agile, so the readers here only cast — they do
# not carry fallback values. Keeping the defaults in exactly one place (init.rb)
# is deliberate: the RedmineUP plugin declares one default and hides the rest in
# readers like this file, which means the stored settings hash and the effective
# configuration disagree, and a `.to_i > 0` check on an undeclared key silently
# reads as false.
#
# Plain `def ... end` throughout: Redmine 5.x still runs on Ruby 2.7, where
# endless method definitions are a syntax error and would break plugin loading.
module RedmineExpertAgile
  COLOR_BASES = %w(none tracker priority status assignee project issue spent_time).freeze
  ESTIMATE_UNITS = %w(hours story_points).freeze

  class << self
    # Stored settings, with any key the administrator has never saved filled in
    # from the defaults declared in init.rb.
    #
    # Redmine returns the stored hash wholesale once the settings form has been
    # submitted even once, so a setting added in a later version is simply
    # absent on an existing installation and reads as nil — which for a numeric
    # setting silently becomes 0. That is how the description excerpt length
    # collapsed to its floor of 20 characters on the dev instance. Merging the
    # declared defaults underneath keeps a stored value authoritative, including
    # a deliberately blank one, while new keys still get their default.
    def settings
      stored = Setting.plugin_redmine_expert_agile || {}
      declared_defaults.merge(stored.to_h)
    end

    def declared_defaults
      plugin = Redmine::Plugin.find(:redmine_expert_agile)
      (plugin && plugin.settings[:default]) || {}
    rescue Redmine::PluginNotFound
      {}
    end

    def setting(key)
      settings[key.to_s]
    end

    def setting?(key)
      setting(key).to_s == '1'
    end

    def setting_int(key)
      setting(key).to_i
    end

    # List-valued setting -> array of non-blank strings.
    #
    # Accepts both storage shapes: text fields store a comma separated string,
    # while a multi-select posts (and Redmine stores) a real Array.
    def setting_list(key)
      value = setting(key)
      items = value.is_a?(Array) ? value : value.to_s.split(',')
      items.map { |item| item.to_s.strip }.reject(&:blank?)
    end

    # --- Board ---------------------------------------------------------

    def default_card_columns
      setting_list(:default_card_columns).map(&:to_sym)
    end

    def issues_per_column
      [setting_int(:issues_per_column), 1].max
    end

    def board_items_limit
      [setting_int(:board_items_limit), 1].max
    end

    def card_description_length
      [setting_int(:card_description_length), 20].max
    end

    def allow_create_card?
      setting?(:allow_create_card)
    end

    def auto_assign_on_move?
      setting?(:auto_assign_on_move)
    end

    def minimize_closed?
      setting?(:minimize_closed)
    end

    # --- Colors --------------------------------------------------------

    def color_base
      base = setting(:color_base).to_s
      COLOR_BASES.include?(base) ? base : 'none'
    end

    def use_colors?
      color_base != 'none'
    end

    def status_colors?
      setting?(:status_colors)
    end

    # --- Estimates -----------------------------------------------------

    def estimate_units
      units = setting(:estimate_units).to_s
      ESTIMATE_UNITS.include?(units) ? units : 'hours'
    end

    def use_story_points?
      setting?(:story_points_on)
    end

    # Empty setting means "every tracker".
    def trackers_for_sp
      setting_list(:trackers_for_sp).map(&:to_i)
    end

    def story_points_for_tracker?(tracker)
      return false unless use_story_points?

      allowed = trackers_for_sp
      allowed.empty? || (tracker && allowed.include?(tracker.id))
    end

    def sp_values
      setting_list(:sp_values).map(&:to_i).uniq.sort
    end

    # --- Sprints -------------------------------------------------------

    def sprints_on?
      setting?(:sprints_on)
    end

    def allow_overlapping_sprints?
      setting?(:allow_overlapping_sprints)
    end

    # --- Charts --------------------------------------------------------

    def default_chart
      value = setting(:default_chart)
      value.present? ? value.to_s : 'burndown'
    end

    def exclude_weekends?
      setting?(:exclude_weekends)
    end

    def hide_closed_issues_data?
      setting?(:hide_closed_issues_data)
    end

    def chart_future_data?
      setting?(:chart_future_data)
    end

    def chart_items_limit
      [setting_int(:chart_items_limit), 1].max
    end

    def chart_cache_minutes
      setting_int(:chart_cache_minutes)
    end

    def chart_cache?
      chart_cache_minutes > 0
    end
  end
end
