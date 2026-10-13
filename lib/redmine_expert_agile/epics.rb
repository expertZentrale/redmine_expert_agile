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
    # How far one epic is along: issues and story points, all and done.
    Progress = Struct.new(:issue_count, :closed_count, :points, :closed_points) do
      def percent
        if points.positive?
          (closed_points * 100.0 / points).round
        elsif issue_count.positive?
          (closed_count * 100.0 / issue_count).round
        else
          0
        end
      end

      # The numbers behind the bar, for its title: issues, then story points
      # where there are any. Plain I18n, so it reads the same on the board,
      # in the planner and on the issue page, whose helpers differ.
      def title
        parts = [::I18n.t(:label_expert_agile_epic_progress_issues, :closed => closed_count, :total => issue_count)]
        if points.positive?
          parts << ::I18n.t(:label_expert_agile_epic_progress_points, :closed => closed_points, :total => points)
        end
        parts.join(' · ')
      end
    end

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

      # {epic_id => progress} for every given epic, in one query.
      #
      # Counts everything below the epic except epics — stories, their
      # subtasks, the stories of a nested epic — that the user may see; done
      # means a closed status. Story points are each issue's own, so a story
      # and its subtasks both count when both are estimated. The percentage
      # follows story points where there are any and falls back to the issue
      # count, so an unestimated epic still shows how far along it is.
      def progress(epics, user = User.current)
        epics = Array(epics).compact
        result = epics.each_with_object({}) { |epic, acc| acc[epic.id] = Progress.new(0, 0, 0, 0) }
        return result if epics.empty?

        # The tree's numbers as they are now, not as the epics were loaded:
        # hanging a story under an epic renumbers the nested set, and the epic
        # objects of a planner loaded before that move would no longer
        # contain the story they just received.
        bounds = Issue.where(:id => epics.map(&:id)).pluck(:id, :root_id, :lft, :rgt)
        bounds = bounds.each_with_object({}) { |(id, root, lft, rgt), acc| acc[id] = [root, lft, rgt] }

        rows = Issue.visible(user)
                    .joins(:status)
                    .joins("LEFT OUTER JOIN #{ExpertAgileData.table_name} ead " \
                           "ON ead.issue_id = #{Issue.table_name}.id")
                    .where(:root_id => bounds.values.map(&:first).uniq)
                    .where.not(:tracker_id => tracker_ids)
                    .pluck("#{Issue.table_name}.root_id", "#{Issue.table_name}.lft",
                           "#{Issue.table_name}.rgt", "#{IssueStatus.table_name}.is_closed",
                           'ead.story_points')
        epics.each do |epic|
          epic_root, epic_lft, epic_rgt = bounds[epic.id]
          next if epic_root.nil?

          inside = rows.select { |root, lft, rgt, _, _| root == epic_root && lft > epic_lft && rgt < epic_rgt }
          closed = inside.select { |row| ActiveModel::Type::Boolean.new.cast(row[3]) }
          result[epic.id] = Progress.new(inside.size, closed.size,
                                         inside.sum { |row| row[4].to_i }, closed.sum { |row| row[4].to_i })
        end
        result
      end

      # The same answer as `nearest`, as an SQL expression over the issues
      # table, for anything that groups in the database. Visibility is left to
      # the query it is used in; the board itself groups the loaded issues in
      # Ruby through `nearest` and never reads this.
      def nearest_epic_sql
        ids = tracker_ids
        return 'NULL' if ids.empty?

        table = Issue.table_name
        "(SELECT ep.id FROM #{table} ep WHERE ep.root_id = #{table}.root_id " \
          "AND ep.lft < #{table}.lft AND ep.rgt > #{table}.rgt " \
          "AND ep.tracker_id IN (#{ids.map(&:to_i).join(',')}) ORDER BY ep.lft DESC LIMIT 1)"
      end

      # Why a card may not be dropped into another epic's lane, or nil when it
      # may. Only the parent link is ever written, so only an issue hanging
      # straight under an epic, or under nothing, can change epics that way:
      # a story's subtask belongs to its epic through the story, and moving it
      # would tear it out of the story. An epic is not dropped into another
      # epic either; nesting epics is a decision for the issue form.
      def lane_refusal(issue)
        return :epic if epic?(issue)

        parent = issue.parent
        return nil if parent.nil? || epic?(parent)

        :subtask
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
