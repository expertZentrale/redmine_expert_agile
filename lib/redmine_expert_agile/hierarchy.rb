# Where a card sits in the subtask tree: its subtasks, and the story it
# belongs to. Both are answered for a whole board in one query each, never by
# asking every card for its `children` or `parent`; and both see only issues
# the user may see, so a card never names a subtask its viewer cannot open.
module RedmineExpertAgile
  module Hierarchy
    # One subtask as a card lists it.
    Child = Struct.new(:id, :subject, :status_name, :closed) do
      def closed?
        closed
      end
    end

    class << self
      # {issue_id => [Child, ...]} for every given issue, in tree order.
      def children(issues, user = User.current)
        issues = Array(issues)
        result = issues.each_with_object({}) { |issue, acc| acc[issue.id] = [] }
        parents = issues.select { |issue| issue.rgt && issue.lft && issue.rgt - issue.lft > 1 }
        return result if parents.empty?

        Issue.visible(user)
             .joins(:status)
             .where(:parent_id => parents.map(&:id))
             .order(:lft)
             .pluck(:parent_id, :id, :subject, "#{IssueStatus.table_name}.name",
                    "#{IssueStatus.table_name}.is_closed")
             .each do |parent_id, id, subject, status, closed|
               result[parent_id] << Child.new(id, subject, status, ActiveModel::Type::Boolean.new.cast(closed))
             end
        result
      end

      # {epic_id => [[issue, depth, children], ...]} — everything visible below
      # each epic in tree order, one query for all of them. Depth counts from
      # the epic's direct children (0); `children` are the row's own
      # subtasks, for its progress. A subtask the user cannot see is left
      # out, and so is everything below it, since its place in the tree would
      # say more than the user may know.
      def descendant_rows(epics, user = User.current)
        epics = Array(epics)
        result = epics.each_with_object({}) { |epic, acc| acc[epic.id] = [] }
        return result if epics.empty?

        issues = Issue.visible(user)
                      .where(:root_id => epics.map(&:root_id).uniq)
                      .includes(:status, :tracker, :assigned_to, :expert_agile_data)
                      .order(:root_id, :lft).to_a
        kids = issues.group_by(&:parent_id)
        epics.each do |epic|
          walk = lambda do |parent, depth|
            (kids[parent.id] || []).each do |issue|
              result[epic.id] << [issue, depth, kids[issue.id] || []]
              walk.call(issue, depth + 1)
            end
          end
          walk.call(epic, 0)
        end
        result
      end

      # {issue_id => parent or nil} for every given issue: the visible parent
      # each one hangs under.
      def parents(issues, user = User.current)
        issues = Array(issues)
        result = issues.each_with_object({}) { |issue, acc| acc[issue.id] = nil }
        ids = issues.map(&:parent_id).compact.uniq
        return result if ids.empty?

        found = Issue.visible(user).where(:id => ids).index_by(&:id)
        issues.each { |issue| result[issue.id] = found[issue.parent_id] if issue.parent_id }
        result
      end
    end
  end
end
