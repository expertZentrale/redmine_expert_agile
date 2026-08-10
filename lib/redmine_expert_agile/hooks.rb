# View hooks. Redmine's own hook points only — no Deface.
#
# Every partial rendered from here emits markup only. Nothing injects a
# <script> tag: behaviour lives in the static assets and reads its data from a
# JSON island, so the plugin stays usable under a `script-src 'self'` policy.
module RedmineExpertAgile
  class Hooks < Redmine::Hook::ViewListener
    # Story point field on the issue create/edit form.
    def view_issues_form_details_bottom(context = {})
      issue = context[:issue]
      return '' unless story_points_visible?(issue)

      context[:hook_caller].send(:render, :partial => 'issues/expert_agile_story_points_form',
                                          :locals => { :f => context[:form], :issue => issue })
    end

    # Story points in the issue attribute table.
    def view_issues_show_details_bottom(context = {})
      issue = context[:issue]
      return '' unless story_points_visible?(issue)
      return '' if issue.story_points.blank?

      context[:hook_caller].send(:render, :partial => 'issues/expert_agile_story_points',
                                          :locals => { :issue => issue })
    end

    # Story points in the bulk edit form.
    def view_issues_bulk_edit_details_bottom(context = {})
      issues = Array(context[:issues])
      return '' unless RedmineExpertAgile.use_story_points?
      return '' unless issues.any? { |issue| issue.story_points_available? }

      context[:hook_caller].send(:render, :partial => 'issues/expert_agile_story_points_bulk_edit')
    end

    private

    def story_points_visible?(issue)
      issue.present? &&
        issue.project&.module_enabled?(:expert_agile) &&
        issue.story_points_available?
    end
  end
end
