# Epics, Jira style, on top of Redmine's own subtask tree.
#
# An epic is an issue of one of the trackers chosen in the plugin settings,
# and an issue belongs to the nearest epic above it in the tree: a story is a
# subtask of its epic, a story's subtasks belong to the same epic through it.
# No table and no custom field of its own, so Redmine's parent filter, the
# REST API, the Gantt chart and the story point roll-up all keep working on
# the same data the board shows.
module RedmineExpertAgile
  module Epics
    class << self
      def tracker_ids
        RedmineExpertAgile.epic_tracker_ids
      end

      def enabled?
        RedmineExpertAgile.epics_on?
      end

      def epic?(issue)
        issue.present? && tracker_ids.include?(issue.tracker_id)
      end

      # {issue_id => nearest epic or nil} for every given issue, in one query
      # whatever the number of issues.
      #
      # Answered from the nested set rather than by walking `parent` up from
      # each card, which is a query per level per card. Only epics the user
      # may see are considered: a card must not reveal the subject of an epic
      # its viewer cannot open. With one hidden, the next visible epic above
      # it is the answer instead.
      def nearest(issues, user = User.current)
        issues = Array(issues)
        result = issues.each_with_object({}) { |issue, acc| acc[issue.id] = nil }
        ids = tracker_ids
        nested = issues.select { |issue| issue.parent_id && issue.root_id }
        return result if ids.empty? || nested.empty?

        # With the tracker: the badge names it, and a lazy load would cost a
        # query per epic on the board.
        epics = Issue.visible(user)
                     .includes(:tracker)
                     .where(:root_id => nested.map(&:root_id).uniq, :tracker_id => ids)
                     .where("#{Issue.table_name}.rgt - #{Issue.table_name}.lft > 1")
                     .to_a
                     .group_by(&:root_id)
        nested.each do |issue|
          above = (epics[issue.root_id] || []).select { |epic| epic.lft < issue.lft && epic.rgt > issue.rgt }
          result[issue.id] = above.max_by(&:lft)
        end
        result
      end
    end
  end
end
