# Keeps agile boards out of the issue list's saved-query sidebar.
#
# ExpertAgileQuery subclasses IssueQuery, which buys us every issue filter and
# the whole visibility model for free. The cost is single-table inheritance:
# `IssueQuery.visible` matches our rows too, and `sidebar_queries` is exactly
# `klass.visible.global_or_on_project(project).sorted`. Without this the issue
# list would offer agile boards as if they were issue queries, and picking one
# would render a board's column set as a flat issue list.
#
# Scoped as narrowly as possible: only a request for plain IssueQuery is
# filtered, and only our own subclass is removed. Any other Query subclass an
# unrelated plugin defines is left alone.
#
# UnboundMethod capture rather than prepend, because QueriesHelper is patched
# with alias_method pairs by the RedmineUP plugins installed alongside.
module RedmineExpertAgile
  module Patches
    module QueriesHelperPatch
      def self.apply!(base = QueriesHelper)
        return if base.instance_variable_get(:@expert_agile_sidebar_patched)

        original = base.instance_method(:sidebar_queries)
        base.send(:define_method, :sidebar_queries) do |klass, project|
          queries = original.bind(self).call(klass, project)
          if klass == IssueQuery
            queries = queries.reject { |query| query.is_a?(ExpertAgileQuery) }
          end
          queries
        end

        base.instance_variable_set(:@expert_agile_sidebar_patched, true)
      end
    end
  end
end
