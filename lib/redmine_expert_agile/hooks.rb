# View hooks. Redmine's own hook points only — no Deface.
#
# Every partial rendered from here emits markup only. Nothing injects a
# <script> tag: behaviour lives in the static assets and reads its data from a
# JSON island, so the plugin stays usable under a `script-src 'self'` policy.
module RedmineExpertAgile
  class Hooks < Redmine::Hook::ViewListener
    # Story point and card colour fields on the issue create/edit form.
    def view_issues_form_details_bottom(context = {})
      issue = context[:issue]
      out = ''.html_safe
      caller = context[:hook_caller]

      if story_points_visible?(issue)
        out << caller.send(:render, :partial => 'issues/expert_agile_story_points_form',
                                    :locals => { :f => context[:form], :issue => issue })
      end
      if card_color_visible?(issue)
        out << caller.send(:render, :partial => 'issues/expert_agile_card_color_form',
                                    :locals => { :issue => issue })
      end
      if sprint_visible?(issue)
        out << caller.send(:render, :partial => 'issues/expert_agile_sprint_form',
                                    :locals => { :f => context[:form], :issue => issue })
      end
      out
    end

    # Renders the sprint id stored in a journal detail as the sprint's name.
    def helper_issues_show_detail_after_setting(context = {})
      detail = context[:detail]
      return unless detail && detail.prop_key == 'expert_agile_sprint_id'

      context[:detail].instance_variable_set(:@expert_agile_labelled, true)
      %i(old_value value).each do |field|
        id = detail.send(field)
        next if id.blank?

        sprint = ExpertAgileSprint.find_by(:id => id)
        detail.send("#{field}=", sprint ? sprint.name : id)
      end
      nil
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
      agile_issue?(issue) && issue.story_points_available?
    end

    # Only worth showing when a board actually colours by issue.
    def card_color_visible?(issue)
      agile_issue?(issue) && RedmineExpertAgile.color_base == 'issue'
    end

    # The sprint selector is only useful once sprints are switched on and the
    # project actually has one to plan into.
    def sprint_visible?(issue)
      return false unless agile_issue?(issue)
      return false unless RedmineExpertAgile.sprints_on?

      issue.project.shared_expert_agile_sprints.available.exists?
    end

    def agile_issue?(issue)
      issue.present? && issue.project.present? &&
        issue.project.module_enabled?(:expert_agile)
    end
  end
end
