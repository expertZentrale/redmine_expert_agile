# Test helper for the expert Agile plugin.
#
# Loads Redmine's own test helper, so the suite needs a Redmine environment
# (a checkout or the container) and cannot run standalone in this repo.
require File.expand_path(File.dirname(__FILE__) + '/../../../test/test_helper')

module RedmineExpertAgile
  module TestHelpers
    # Runs the block with the given plugin settings applied, restoring the
    # previous hash afterwards. Values are strings, matching how Redmine stores
    # plugin settings.
    def with_agile_settings(settings)
      previous = Setting.plugin_redmine_expert_agile
      Setting.plugin_redmine_expert_agile = previous.merge(settings.stringify_keys)
      yield
    ensure
      Setting.plugin_redmine_expert_agile = previous
    end
  end
end

ActiveSupport::TestCase.include(RedmineExpertAgile::TestHelpers)
