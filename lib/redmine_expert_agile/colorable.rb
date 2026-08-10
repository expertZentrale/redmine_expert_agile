# Gives a model an optional agile card colour.
#
# Included explicitly into the handful of models that need it — Issue, Project,
# Tracker, IssuePriority, IssueStatus — and nowhere else. RedmineUP mixes the
# equivalent into `ActiveRecord::Base`, i.e. into every model in the entire
# Redmine instance, plugins included.
module RedmineExpertAgile
  module Colorable
    def self.included(base)
      base.class_eval do
        has_one :expert_agile_color, :as => :container, :dependent => :destroy

        # A colour set on an unsaved record has nothing to point at yet, so it
        # is held until the container has an id.
        after_save :persist_expert_agile_color, :if => :expert_agile_color_pending?
      end
    end

    # Builds the row on demand so callers never have to check for it.
    def expert_agile_color!
      expert_agile_color || build_expert_agile_color
    end

    def color
      expert_agile_color && expert_agile_color.color
    end

    # Writes through immediately for a persisted record — the admin colour
    # screen and console usage expect that — and defers for a new one until
    # after_save.
    def color=(value)
      @expert_agile_pending_color = value.presence
      if new_record?
        @expert_agile_color_pending = true
      else
        persist_expert_agile_color
      end
      value
    end

    private

    def expert_agile_color_pending?
      @expert_agile_color_pending.present?
    end

    def persist_expert_agile_color
      @expert_agile_color_pending = false
      if @expert_agile_pending_color.nil?
        expert_agile_color.destroy if expert_agile_color
      else
        record = expert_agile_color!
        record.color = @expert_agile_pending_color
        record.save!
      end
      association(:expert_agile_color).reload
    end
  end
end
