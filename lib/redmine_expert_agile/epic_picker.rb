# The epic picker on Redmine's issue form.
#
# An epic is the parent task, so picking one writes Redmine's own "Parent
# task" field and nothing else: saving, validation, permissions and the
# journal stay core's, and core already redraws the form whenever that field
# changes. This module answers what the picker offers on one form, and
# `expert_agile_epic_picker.js` draws it next to the parent field.
module RedmineExpertAgile
  module EpicPicker
    class << self
      # Whether an issue's form offers the picker: in a project that plans
      # with epics, to a user who may set the parent task, and not on an epic
      # itself, whose parent is a question of nesting epics.
      def offered?(issue, user = User.current)
        issue.is_a?(Issue) && issue.project.present? &&
          RedmineExpertAgile::Epics.planned_in?(issue.project) &&
          !RedmineExpertAgile::Epics.epic?(issue) &&
          issue.safe_attribute?('parent_issue_id', user)
      end

      # The picker's JSON island, or nil where the form offers none.
      #
      # Two shapes. An issue under nothing or straight under an epic chooses
      # from the open epics (`epics`, with `current` the chosen one). An issue
      # under anything else belongs to its epic through that parent, and a
      # new epic would tear it out of its parent: it only shows the epic and
      # the parent it comes through (`via`), like a board lane refuses such a
      # card. A parent the user cannot see, or a number that is no issue at
      # all, counts as anything else; the epic then shows once it is saved.
      def data(issue, user = User.current)
        return nil unless offered?(issue, user)

        parent_id = issue.parent_issue_id
        parent = parent_id.present? ? Issue.visible(user).find_by(:id => parent_id) : nil
        if parent_id.present? && !RedmineExpertAgile::Epics.epic?(parent)
          epic = parent && RedmineExpertAgile::Epics.nearest([parent], user)[parent.id]
          progress = RedmineExpertAgile::Epics.progress([epic].compact, user)
          return {
            :via => parent_id.to_s,
            :current => epic && entry(epic, issue, progress[epic.id]),
            :labels => labels(parent_id)
          }
        end

        epics = choices(issue, parent, user)
        progress = RedmineExpertAgile::Epics.progress(epics, user)
        {
          :current => parent && parent.id.to_s,
          :epics => epics.map { |epic| entry(epic, issue, progress[epic.id]) },
          :labels => labels
        }
      end

      private

      # The open epics of the project tree the issue may hang under, by
      # subject, as in the planner's epic panel. Core decides which projects
      # a parent may come from (`valid_parent_project?`), and an issue never
      # goes under its own subtree. The current epic stays a choice when it
      # is closed, so the form still names it.
      def choices(issue, current, user)
        scope = RedmineExpertAgile::Epics.open_scope(issue.project, user).includes(:project, :status)
        if issue.persisted? && !issue.leaf?
          scope = scope.where.not(:id => issue.self_and_descendants.reorder(nil).select(:id))
        end
        epics = scope.order(:subject).to_a.select { |epic| issue.valid_parent_project?(epic) }
        epics.unshift(current) if current && !epics.include?(current)
        epics
      end

      # One epic as the picker shows it: the badge's colour, the progress bar
      # of the board and the planner, and its project where that is not the
      # issue's own.
      def entry(epic, issue, progress)
        {
          :id => epic.id.to_s,
          :subject => epic.subject,
          :project => (epic.project.name if epic.project_id != issue.project_id),
          :color => ExpertAgileColor.for_principal(epic),
          :percent => progress.percent,
          :done => progress.closed_count,
          :total => progress.issue_count,
          :title => progress.title,
          :closed => epic.closed?
        }
      end

      def labels(via = nil)
        labels = {
          :none => ::I18n.t(:label_expert_agile_epic_picker_none),
          :search => ::I18n.t(:label_expert_agile_epic_picker_search),
          :list => ::I18n.t(:label_expert_agile_epic_plural),
          :noMatch => ::I18n.t(:text_expert_agile_epic_picker_no_match),
          :closed => ::I18n.t(:label_closed_issues)
        }
        labels[:via] = ::I18n.t(:text_expert_agile_epic_picker_via, :id => via) if via
        labels
      end
    end
  end
end
