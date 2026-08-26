# Redmine expert Agile Plugin
#
# Copyright (C) 2026 Dennis Buehring
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version. See LICENSE for the full text.
#
# Agile boards for Redmine: a Kanban/Scrum board built on Redmine's own query
# system, story points, sprints with a backlog planner, and burndown/burnup/
# velocity/cumulative-flow/cycle-time charts.
#
# Naming note: "expert" is the company name and is always written with a
# lowercase "e" in user-facing text. Code identifiers keep their normal casing.

require File.expand_path('../lib/redmine_expert_agile', __FILE__)
require File.expand_path('../lib/redmine_expert_agile/board_column', __FILE__)
require File.expand_path('../lib/redmine_expert_agile/board_grid', __FILE__)
require File.expand_path('../lib/redmine_expert_agile/board_positions', __FILE__)
require File.expand_path('../lib/redmine_expert_agile/colorable', __FILE__)
require File.expand_path('../lib/redmine_expert_agile/card_color', __FILE__)
require File.expand_path('../lib/redmine_expert_agile/journal_projection', __FILE__)
require File.expand_path('../lib/redmine_expert_agile/charts/base', __FILE__)
require File.expand_path('../lib/redmine_expert_agile/charts/burndown', __FILE__)
require File.expand_path('../lib/redmine_expert_agile/charts/burnup', __FILE__)
require File.expand_path('../lib/redmine_expert_agile/charts/cumulative_flow', __FILE__)
require File.expand_path('../lib/redmine_expert_agile/charts/velocity', __FILE__)
require File.expand_path('../lib/redmine_expert_agile/charts/cycle_time', __FILE__)
require File.expand_path('../lib/redmine_expert_agile/charts/registry', __FILE__)
require File.expand_path('../lib/redmine_expert_agile/hooks', __FILE__)
require File.expand_path('../lib/redmine_expert_agile/patches/issue_patch', __FILE__)
require File.expand_path('../lib/redmine_expert_agile/patches/project_patch', __FILE__)
require File.expand_path('../lib/redmine_expert_agile/patches/projects_helper_patch', __FILE__)
require File.expand_path('../lib/redmine_expert_agile/patches/issue_query_patch', __FILE__)
require File.expand_path('../lib/redmine_expert_agile/patches/issues_controller_patch', __FILE__)
require File.expand_path('../lib/redmine_expert_agile/patches/queries_helper_patch', __FILE__)

Redmine::Plugin.register :redmine_expert_agile do
  name 'Redmine expert Agile'
  author 'Dennis Buehring'
  description 'Agile boards, story points, sprints and charts for Redmine'
  version '0.2.3'
  requires_redmine :version_or_higher => '5.0'
  url 'https://github.com/expertZentrale/redmine_expert_agile'

  # Every default is declared here on purpose. The RedmineUP plugin declares
  # only one default and hides the rest in reader methods, so a fresh install
  # has an almost empty settings hash and every `.to_i > 0` check silently
  # reads as false. All values are strings ('0'/'1' for booleans), matching
  # the convention used by redmine_expert_helpdesk.
  settings :partial => 'settings/expert_agile_settings',
           :default => {
             # --- Board -------------------------------------------------
             # Card fields shown by default on a new board (comma separated).
             'default_card_columns'    => 'tracker,assigned_to',
             # Cards rendered per column before "load more" kicks in.
             'issues_per_column'       => '10',
             # Hard cap on issues pulled into one board render.
             'board_items_limit'       => '500',
             # Characters of the description shown on a card, when the
             # description field is switched on for that board.
             'card_description_length' => '140',
             'allow_create_card'       => '0',
             'auto_assign_on_move'     => '0',
             'minimize_closed'         => '0',

             # --- Colors ------------------------------------------------
             # none | tracker | priority | status | assignee | project | issue | spent_time
             # Defaults to tracker so a fresh board is colour-coded without
             # anyone having to assign colours first.
             'color_base'              => 'tracker',
             'status_colors'           => '1',

             # --- Estimates ---------------------------------------------
             # hours | story_points — the unit shown on cards and totals.
             'estimate_units'          => 'hours',
             'story_points_on'         => '0',
             # Empty means "all trackers".
             'trackers_for_sp'         => '',
             # Suggested values in the story point selector (modified Fibonacci).
             'sp_values'               => '0,1,2,3,5,8,13,20,40,100',

             # --- Sprints -----------------------------------------------
             'sprints_on'              => '0',
             'allow_overlapping_sprints' => '0',

             # --- Charts ------------------------------------------------
             'default_chart'           => 'burndown',
             'exclude_weekends'        => '0',
             'hide_closed_issues_data' => '0',
             'chart_future_data'       => '0',
             # Cap for the journal-projection charts.
             'chart_items_limit'       => '1000',
             # Minutes to cache computed chart series (0 disables caching).
             'chart_cache_minutes'     => '60'
           }

  # Board, charts and sprints.
  project_module :expert_agile do
    permission :view_expert_agile_board,
               { :expert_agile_boards  => [:index, :issue_tooltip, :agile_data],
                 :expert_agile_queries => [:index] },
               :read => true
    permission :edit_expert_agile_board,
               { :expert_agile_boards => [:update, :create_issue, :edit_issue, :update_issue] },
               :require => :member
    # Every variant of the query controller — board, chart and backlog — or
    # saving that kind is refused: find_optional_project authorises the
    # controller/action pair, so an action missing from every permission map is
    # simply denied.
    #
    # The backlog variant is listed here rather than in the backlog module
    # because saving is one permission across all three screens. The
    # consequence is that a project running the backlog module without the board
    # module can filter its backlog but not save one.
    permission :add_expert_agile_queries,
               { :expert_agile_queries => [:new, :create, :edit, :update, :destroy],
                 :expert_agile_charts_queries => [:new, :create, :edit, :update, :destroy],
                 :expert_agile_backlog_queries => [:new, :create, :edit, :update, :destroy] },
               :require => :loggedin
    permission :manage_public_expert_agile_queries,
               { :expert_agile_queries => [:new, :create, :edit, :update, :destroy],
                 :expert_agile_charts_queries => [:new, :create, :edit, :update, :destroy],
                 :expert_agile_backlog_queries => [:new, :create, :edit, :update, :destroy] },
               :require => :member
    permission :view_expert_agile_charts,
               { :expert_agile_charts         => [:show, :render_chart],
                 :expert_agile_charts_queries => [:index] },
               :read => true
    permission :manage_expert_agile_sprints,
               { :expert_agile_sprints => [:index, :show, :new, :create, :edit, :update, :destroy] },
               :require => :member
  end

  # One entry in the administration menu, named after the plugin and pointing at
  # its settings — the shape redmine_expert_helpdesk already uses, so the two
  # sit together and read as belonging to something.
  #
  # The card colour screen is reached from the colour section of those settings
  # rather than as a second top-level entry: as one it stood among Redmine's own
  # areas under a bare functional name ("Card colours of Agile") that said
  # nothing about which plugin owns it.
  admin_menu_options = { :caption => :label_expert_agile }
  if Redmine::VERSION::MAJOR >= 6
    # `plugin:` makes Redmine resolve the icon against
    # plugin_assets/redmine_expert_agile/icons.svg, so the name has to be one
    # this plugin ships. The entry used to ask for 'palette' with no sprite in
    # the plugin at all, which left it as the one item in the menu with a
    # missing icon.
    admin_menu_options[:icon] = 'expert-agile'
    admin_menu_options[:plugin] = :redmine_expert_agile
    admin_menu_options[:html] = { :class => 'icon' }
  else
    admin_menu_options[:html] = { :class => 'icon icon-settings' }
  end
  menu :admin_menu, :redmine_expert_agile,
       { :controller => 'settings', :action => 'plugin', :id => 'redmine_expert_agile' },
       admin_menu_options

  # Board entry in the project menu, next to the other planning views.
  # The module gating does the visibility work, so no :if proc is needed.
  agile_menu_options = { :caption => :label_expert_agile_board, :after => :gantt,
                         :param => :project_id }
  agile_menu_options[:plugin] = :redmine_expert_agile if Redmine::VERSION::MAJOR >= 6
  menu :project_menu, :expert_agile,
       { :controller => 'expert_agile_boards', :action => 'index' },
       agile_menu_options

  charts_menu_options = { :caption => :label_expert_agile_charts, :after => :expert_agile,
                          :param => :project_id }
  charts_menu_options[:plugin] = :redmine_expert_agile if Redmine::VERSION::MAJOR >= 6
  menu :project_menu, :expert_agile_charts,
       { :controller => 'expert_agile_charts', :action => 'show' },
       charts_menu_options

  # Backlog planner. Separate module so a project can run a plain Kanban board
  # without the backlog UI, mirroring how RedmineUP splits :agile/:agile_backlog.
  project_module :expert_agile_backlog do
    permission :view_expert_agile_backlog,
               { :expert_agile_backlogs => [:index, :load_more, :autocomplete],
                 :expert_agile_backlog_queries => [:index] },
               :read => true
    permission :manage_expert_agile_backlog,
               { :expert_agile_backlogs => [:update] },
               :require => :member
  end

  backlog_menu_options = { :caption => :label_expert_agile_backlog,
                           :after => :expert_agile_charts, :param => :project_id }
  backlog_menu_options[:plugin] = :redmine_expert_agile if Redmine::VERSION::MAJOR >= 6
  menu :project_menu, :expert_agile_backlog,
       { :controller => 'expert_agile_backlogs', :action => 'index' },
       backlog_menu_options
end

# Patches are applied here, at the bottom of init.rb, rather than from a
# Rails.configuration.to_prepare block. Redmine already executes init.rb inside
# a to_prepare callback (PluginLoader#run_initializer) and re-runs it on every
# reload in development; a to_prepare registered from in here would never fire
# in production, because the callbacks have already been copied into the
# reloader by that point.
RedmineExpertAgile::Patches::IssuePatch.apply!

# Colour support goes only into the models that can actually be coloured.
# RedmineUP mixes its equivalent into ActiveRecord::Base, i.e. every model in
# the instance.
[Issue, Project, Tracker, IssuePriority, IssueStatus].each do |model|
  model.include(RedmineExpertAgile::Colorable) unless model.included_modules.include?(RedmineExpertAgile::Colorable)
end

RedmineExpertAgile::Patches::IssueQueryPatch.apply!
RedmineExpertAgile::Patches::IssuesControllerPatch.apply!
RedmineExpertAgile::Patches::QueriesHelperPatch.apply!
RedmineExpertAgile::Patches::ProjectPatch.apply!
RedmineExpertAgile::Patches::ProjectsHelperPatch.apply!
