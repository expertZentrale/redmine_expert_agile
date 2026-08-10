# Exposes story points as a column and a filter on the core issue list.
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
          columns
        end

        original_filters = base.instance_method(:initialize_available_filters)
        filters_visibility = base.private_method_defined?(:initialize_available_filters) ? :private : :public
        base.send(:define_method, :initialize_available_filters) do
          original_filters.bind(self).call
          add_available_filter('story_points', :type => :integer,
                                               :name => l(:label_expert_agile_story_points))
        end
        base.send(filters_visibility, :initialize_available_filters)

        base.instance_variable_set(:@expert_agile_query_patched, true)
      end

      module SqlMethods
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
