# Two things on the issues controller: the story point field in bulk edit, and
# the helper the colour field needs.
#
# Makes the story point field behave like every other field in Redmine's bulk
# edit form: blank means "leave unchanged", 'none' means "clear the value".
#
# UnboundMethod capture rather than prepend + super, for the same reason as
# IssueQueryPatch: RedmineUP's redmine_agile aliases
# IssuesController#parse_params_for_bulk_update, and a prepended `super` gets
# captured into their `_without_agile` alias, producing infinite recursion.
module RedmineExpertAgile
  module Patches
    module IssuesControllerPatch
      def self.apply!(base = IssuesController)
        # Redmine turns off Rails' automatic helper inclusion, so a plugin
        # helper is only there for the controller of the same name. The colour
        # field is rendered into the issue form through a hook, in this
        # controller's view context, and without this its swatches raise.
        base.helper(ExpertAgileColorsHelper)

        return if base.instance_variable_get(:@expert_agile_bulk_edit_patched)

        original = base.instance_method(:parse_params_for_bulk_update)
        visibility = base.private_method_defined?(:parse_params_for_bulk_update) ? :private : :public

        base.send(:define_method, :parse_params_for_bulk_update) do |params|
          attributes = original.bind(self).call(params)
          nested = attributes['expert_agile_data_attributes'] ||
                   attributes[:expert_agile_data_attributes]
          next attributes if nested.blank?

          points = nested['story_points'] || nested[:story_points]
          if points.blank?
            # Untouched field: drop the nested hash entirely so a bulk edit of
            # unrelated attributes cannot wipe existing story points.
            attributes.delete('expert_agile_data_attributes')
            attributes.delete(:expert_agile_data_attributes)
          elsif points == 'none'
            nested['story_points'] = nil
          end
          attributes
        end
        base.send(visibility, :parse_params_for_bulk_update)

        base.instance_variable_set(:@expert_agile_bulk_edit_patched, true)
      end
    end
  end
end
