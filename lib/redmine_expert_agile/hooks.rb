# View hooks. Redmine's own hook points only — no Deface.
#
# Every partial rendered from here emits markup only. Nothing injects a
# <script> tag: behaviour lives in the static assets and reads its data from a
# JSON island, so the plugin stays usable under a `script-src 'self'` policy.
module RedmineExpertAgile
  class Hooks < Redmine::Hook::ViewListener
    # Story point and sprint fields on the issue create/edit form.
    def view_issues_form_details_bottom(context = {})
      issue = context[:issue]
      out = ''.html_safe
      caller = context[:hook_caller]

      if story_points_visible?(issue)
        out << caller.send(:render, :partial => 'issues/expert_agile_story_points_form',
                                    :locals => { :f => context[:form], :issue => issue })
      end
      if sprint_visible?(issue)
        out << caller.send(:render, :partial => 'issues/expert_agile_sprint_form',
                                    :locals => { :f => context[:form], :issue => issue })
      end
      out
    end

    # Renders the sprint id stored in a journal detail as the sprint's name.
    #
    # Only a sprint the reader could see anyway is named; any other stays a
    # bare id. A journal can carry a sprint the issue's project was never meant
    # to plan into (written before that was validated), and naming it here
    # would hand the sprint names of every project in the instance to anyone
    # able to read the issue.
    def helper_issues_show_detail_after_setting(context = {})
      detail = context[:detail]
      return unless detail && detail.prop_key == 'expert_agile_sprint_id'

      context[:detail].instance_variable_set(:@expert_agile_labelled, true)
      issue = detail.journal && detail.journal.journalized
      %i(old_value value).each do |field|
        id = detail.send(field)
        next if id.blank?

        sprint = nameable_sprint(id, issue)
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

    # A sprint shared with the issue's project is offered on that issue's form,
    # so its name is no secret to the reader; any other is named only when its
    # own project lets the reader see the board.
    def nameable_sprint(id, issue)
      sprint = ExpertAgileSprint.find_by(:id => id)
      return nil if sprint.nil?
      return sprint if issue.is_a?(Issue) && sprint.shared_with?(issue.project)
      return sprint if ExpertAgileSprint.visible.where(:id => sprint.id).exists?

      nil
    end

    def story_points_visible?(issue)
      agile_issue?(issue) && issue.story_points_available?
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
