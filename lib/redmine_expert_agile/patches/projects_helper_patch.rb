# Adds the "Sprints" tab to the project settings.
#
# UnboundMethod capture, not prepend + super. project_settings_tabs is the
# single most contested method in the Redmine plugin ecosystem — redmine_agile,
# redmine_contacts and redmine_contacts_helpdesk all wrap it with alias_method
# pairs, and prepend collides with every one of them ("super: no superclass
# method"). Calling an explicitly captured original is immune to ordering and
# to chaining.
module RedmineExpertAgile
  module Patches
    module ProjectsHelperPatch
      def self.apply!(base = ProjectsHelper)
        return if base.instance_variable_get(:@expert_agile_tabs_patched)

        original = base.instance_method(:project_settings_tabs)
        base.send(:define_method, :project_settings_tabs) do
          tabs = original.bind(self).call
          if User.current.allowed_to?(:manage_expert_agile_sprints, @project) &&
             @project.module_enabled?(:expert_agile)
            # Named expert_agile_sprints, not 'sprints': RedmineUP registers
            # tabs of its own and identical names collide on the DOM id, leaving
            # one tab showing the wrong content.
            tabs << {
              :name => 'expert_agile_sprints',
              :action => :manage_expert_agile_sprints,
              :partial => 'projects/settings/expert_agile_sprints',
              :label => :label_expert_agile_sprint_plural
            }
          end
          tabs
        end
        base.instance_variable_set(:@expert_agile_tabs_patched, true)
      end
    end
  end
end
