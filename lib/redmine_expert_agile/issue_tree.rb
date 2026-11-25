# Epics on Redmine's own issue list.
#
# Sorted by parent task, the issue list already shows the subtask tree: core
# indents every issue under its parent. What it cannot tell is which rows are
# epics. This module answers that for the rows of one page — which rows are
# epics, with their colour and progress, and which epic every other row
# belongs to — and `expert_agile_issue_tree.js` turns the answer into
# highlighted epic rows that fold away their stories.
#
# It also builds the "Epics and stories" link of the issue sidebar. The link
# carries the whole list in its parameters rather than pointing to a saved
# query: a public query is either one project's or every project's, and most
# projects of an instance plan without epics.
module RedmineExpertAgile
  module IssueTree
    class << self
      # Whether a list is in tree order. Any other order tears an epic's
      # stories apart, and the list is left as core draws it.
      def applies?(query)
        RedmineExpertAgile::Epics.enabled? && query.is_a?(IssueQuery) &&
          query.sort_criteria.first_key == 'parent'
      end

      # The epics and epic members among the given rows, for the JSON island.
      # Nil when there is neither, so a list without epics gets nothing.
      #
      # Two queries for the whole page whatever its size: the nearest epics
      # of the rows and the progress of the epic rows. Both only count what
      # the user may see.
      def data(issues, user = User.current)
        issues = Array(issues)
        epic_rows = issues.select { |issue| RedmineExpertAgile::Epics.epic?(issue) }
        nearest = RedmineExpertAgile::Epics.nearest(issues - epic_rows, user).compact
        return nil if epic_rows.empty? && nearest.empty?

        progress = RedmineExpertAgile::Epics.progress(epic_rows, user)
        epics = {}
        nearest.each_value { |epic| epics[epic.id.to_s] ||= { :color => colour(epic) } }
        epic_rows.each do |epic|
          done = progress[epic.id]
          epics[epic.id.to_s] = {
            :color => colour(epic),
            :progress => ::I18n.t(:label_expert_agile_epic_progress_issues,
                                  :closed => done.closed_count, :total => done.issue_count),
            :title => done.title
          }
        end

        {
          :epics => epics,
          :members => nearest.each_with_object({}) { |(id, epic), acc| acc[id.to_s] = epic.id.to_s },
          :labels => {
            :collapse => ::I18n.t(:label_expert_agile_epic_collapse),
            :expand => ::I18n.t(:label_expert_agile_epic_expand),
            :collapseAll => ::I18n.t(:label_expert_agile_epics_collapse_all),
            :expandAll => ::I18n.t(:label_expert_agile_epics_expand_all)
          }
        }
      end

      # Whether a project's issue sidebar offers the epic views: where it
      # plans with expert Agile and has an epic tracker of its own.
      def views_offered?(project)
        return false if project.nil? || !RedmineExpertAgile::Epics.enabled?
        return false unless project.module_enabled?(:expert_agile) || project.module_enabled?(:expert_agile_backlog)

        project.trackers.where(:id => RedmineExpertAgile::Epics.tracker_ids).exists?
      end

      # The issue list of the "Epics and stories" link: every status, in tree
      # order, with the columns that show where a story stands.
      def tree_list_params
        columns = %w(tracker status subject assigned_to)
        columns << 'expert_agile_sprint' if RedmineExpertAgile.sprints_on?
        columns << 'done_ratio'
        {
          :set_filter => '1',
          :f => ['status_id'],
          :op => { 'status_id' => '*' },
          :c => columns,
          :sort => 'parent'
        }
      end

      private

      # The same colour as the epic's badge on the board.
      def colour(epic)
        ExpertAgileColor.for_principal(epic)
      end
    end
  end
end
