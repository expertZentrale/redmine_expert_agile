# Exposes story points and the sprint as columns and filters on the core
# issue list.
#
# Wrapped by UnboundMethod capture, NOT prepend + super. Both RedmineUP plugins
# installed here (`redmine_agile`, `redmine_contacts_helpdesk`) patch
# IssueQuery#available_columns and #initialize_available_filters with
# alias_method pairs. If our module is prepended before their alias runs, their
# `alias_method :available_columns_without_x, :available_columns` captures *our*
# prepended method as the "original"; our `super` then reaches their
# `_with_x` method, which calls `_without_x` — straight back into us. The result
# is a SystemStackError on the first query. Calling an explicitly captured
# UnboundMethod is immune to ordering and to chaining.
#
# Deliberately does NOT touch the database at load time. RedmineUP guards the
# equivalent patch with `ActiveRecord::Base.connection.tables.include?(...)`,
# which opens a connection while classes are still loading and breaks
# `rake db:create` on an empty database. The column and filter are declared
# unconditionally; they only hit the table when a query actually runs.
module RedmineExpertAgile
  module Patches
    module IssueQueryPatch
      # Correlated subquery so the column can be sorted without forcing a join
      # onto every issue query.
      def self.story_points_sql
        "(SELECT ead.story_points FROM #{ExpertAgileData.table_name} ead " \
          "WHERE ead.issue_id = #{Issue.table_name}.id)"
      end

      # Whether a query offers the sprint: everywhere for a cross-project
      # list, in a project only where one of the plugin's modules is on, so a
      # project without it never sees an empty sprint filter.
      def self.sprints_offered?(project)
        project.nil? || project.module_enabled?(:expert_agile) || project.module_enabled?(:expert_agile_backlog)
      end

      # The sprints a query can filter by, most relevant first: the ones the
      # project may plan into, or every sprint the user may see on a
      # cross-project list, which then names each sprint's project. The
      # active sprint comes first as a value of its own, resolved when the
      # query runs, so a saved list follows the iteration.
      def self.sprint_filter_values(project)
        values = [[::I18n.t(:label_expert_agile_sprint_active_mode), 'active']]
        sprints = project ? project.shared_expert_agile_sprints : ExpertAgileSprint.visible.includes(:project)
        sprints.sorted.each do |sprint|
          label = "#{sprint.name} (#{::I18n.t("label_expert_agile_sprint_status_#{sprint.status_name}")})"
          label = "#{sprint.project.name} » #{label}" if project.nil?
          values << [label, sprint.id.to_s]
        end
        values
      end

      def self.apply!(base = IssueQuery)
        return if base.instance_variable_get(:@expert_agile_query_patched)

        # New method, no core name to collide with — a plain include is fine.
        base.include(SqlMethods)

        original_columns = base.instance_method(:available_columns)
        base.send(:define_method, :available_columns) do
          columns = original_columns.bind(self).call
          # The core method memoizes, so `columns` is the same array on every
          # call — append only once.
          unless columns.any? { |column| column.name == :story_points }
            columns << QueryColumn.new(
              :story_points,
              :sortable => RedmineExpertAgile::Patches::IssueQueryPatch.story_points_sql,
              :groupable => false,
              :caption => :label_expert_agile_story_points
            )
          end
          # The issue list only: the board and the planner load their cards
          # their own way and pick their sprint in their options instead.
          if !is_a?(ExpertAgileQuery) &&
             RedmineExpertAgile::Patches::IssueQueryPatch.sprints_offered?(project) &&
             columns.none? { |column| column.name == :expert_agile_sprint }
            columns << RedmineExpertAgile::SprintQueryColumn.new(self)
          end
          columns
        end

        original_filters = base.instance_method(:initialize_available_filters)
        filters_visibility = base.private_method_defined?(:initialize_available_filters) ? :private : :public
        base.send(:define_method, :initialize_available_filters) do
          original_filters.bind(self).call
          add_available_filter('story_points', :type => :integer,
                                               :name => l(:label_expert_agile_story_points))
          if RedmineExpertAgile::Patches::IssueQueryPatch.sprints_offered?(project)
            query_project = project
            add_available_filter('expert_agile_sprint_id',
                                 :type => :list_optional, :name => l(:label_expert_agile_sprint),
                                 :values => lambda {
                                   RedmineExpertAgile::Patches::IssueQueryPatch.sprint_filter_values(query_project)
                                 })
          end
        end
        base.send(filters_visibility, :initialize_available_filters)

        # The list's rows carry their agile data and sprint, so the story
        # points and sprint columns cost one query for the page, not one per
        # row. `issues` is aliased by both RedmineUP plugins — captured here
        # for the reason at the top of this file.
        original_issues = base.instance_method(:issues)
        base.send(:define_method, :issues) do |*args|
          rows = original_issues.bind(self).call(*args)
          # Grouping by sprint reads every row's sprint even when the column
          # itself is not shown.
          if has_column?(:expert_agile_sprint) || group_by.to_s == 'expert_agile_sprint'
            RedmineExpertAgile.preload(rows, :expert_agile_data => :sprint)
          elsif has_column?(:story_points)
            RedmineExpertAgile.preload(rows, :expert_agile_data)
          end
          rows
        end

        # A column grouped by a record's id in SQL hands back the records, so
        # the counts are keyed the way its group_value looks them up. Core does
        # the same only for custom fields.
        original_grouped = base.instance_method(:grouped_query)
        grouped_visibility = base.private_method_defined?(:grouped_query) ? :private : :public
        base.send(:define_method, :grouped_query) do |&block|
          result = original_grouped.bind(self).call(&block)
          column = group_by_column
          next result unless result.is_a?(Hash) && column.respond_to?(:group_records)

          records = column.group_records(result.keys.compact)
          result.each_with_object({}) { |(key, value), mapped| mapped[key.nil? ? nil : records[key.to_i]] = value }
        end
        base.send(grouped_visibility, :grouped_query)

        base.instance_variable_set(:@expert_agile_query_patched, true)
      end

      module SqlMethods
        # Through the agile data row, as a subquery on issue ids like the
        # story points: an issue never planned has no row, and "not in sprint
        # X" has to keep it.
        def sql_for_expert_agile_sprint_id_field(_field, operator, value)
          table = ExpertAgileData.table_name
          case operator
          when '*', '!*'
            planned = "SELECT issue_id FROM #{table} WHERE sprint_id IS NOT NULL"
            "#{Issue.table_name}.id #{operator == '*' ? 'IN' : 'NOT IN'} (#{planned})"
          else
            ids = expert_agile_sprint_filter_ids(value)
            return(operator == '!' ? '1=1' : '1=0') if ids.empty?

            in_sprints = "SELECT issue_id FROM #{table} WHERE sprint_id IN (#{ids.join(',')})"
            "#{Issue.table_name}.id #{operator == '!' ? 'NOT IN' : 'IN'} (#{in_sprints})"
          end
        end

        # The filter's values as sprint ids, "active" resolved now. In a
        # project that is the one sprint its board follows — the project's
        # own running sprint, else one shared with it — so a project that has
        # both does not get two iterations' issues. Across projects it is
        # every active sprint the user may see.
        def expert_agile_sprint_filter_ids(values)
          Array(values).flat_map do |value|
            if value.to_s == 'active'
              if project
                active = project.shared_expert_agile_sprints.active
                sprint = active.find_by(:project_id => project.id) || active.sorted.first
                sprint ? [sprint.id] : []
              else
                ExpertAgileSprint.visible.active.pluck(:id)
              end
            else
              value.to_s =~ /\A\d+\z/ ? [value.to_i] : []
            end
          end.uniq
        end

        # Filtering goes through a subquery on issue ids rather than through
        # `sql_for_field` against the correlated expression: sql_for_field always
        # builds "#{db_table}.#{db_field}", so it cannot take an expression.
        #
        # Issues with no expert_agile_data row have no story points, so the
        # negative operators must be NOT IN — an inner comparison would never
        # match them and "story points is not 5" would silently drop every
        # unestimated issue.
        def sql_for_story_points_field(field, operator, value)
          table = ExpertAgileData.table_name
          estimated = "SELECT issue_id FROM #{table} WHERE story_points IS NOT NULL"

          case operator
          when '*'  # any value set
            "#{Issue.table_name}.id IN (#{estimated})"
          when '!*' # no value set
            "#{Issue.table_name}.id NOT IN (#{estimated})"
          when '!'  # not equal to the given values
            inner = sql_for_field(field, '=', value, table, 'story_points')
            "#{Issue.table_name}.id NOT IN (SELECT issue_id FROM #{table} WHERE #{inner})"
          else
            inner = sql_for_field(field, operator, value, table, 'story_points')
            "#{Issue.table_name}.id IN (SELECT issue_id FROM #{table} WHERE #{inner})"
          end
        end
      end
    end
  end
end
