# View hooks. Redmine's own hook points only — no Deface.
#
# Every partial rendered from here emits markup only. Nothing injects a
# <script> tag: behaviour lives in the static assets and reads its data from a
# JSON island, so the plugin stays usable under a `script-src 'self'` policy.
module RedmineExpertAgile
  class Hooks < Redmine::Hook::ViewListener
    # The card colour field is rendered into the issue form by a hook, far too
    # late to add anything to the layout's head. Issue pages therefore get the
    # plugin's colour assets from here — without the stylesheet the picker has
    # no layout, and without the script its "current colour" field stops
    # following what is clicked.
    def view_layouts_base_html_head(context = {})
      return '' unless colour_picker_reachable?(context)

      stylesheet_link_tag('expert_agile', :plugin => 'redmine_expert_agile') +
        javascript_include_tag('expert_agile_colors', :plugin => 'redmine_expert_agile')
    end

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

    # Narrow on purpose: this runs on every page, and the assets are only of use
    # where the colour field can actually turn up — an issue page, in a project
    # on the module, with boards set to colour by issue.
    def colour_picker_reachable?(context)
      return false unless context[:controller].is_a?(IssuesController)
      return false unless RedmineExpertAgile.color_base == 'issue'

      project = context[:project]
      project.nil? || project.module_enabled?(:expert_agile)
    end

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
