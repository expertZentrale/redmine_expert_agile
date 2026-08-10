# Adds the agile payload to Issue: the has_one association, story point
# accessors, and a rank-ordered scope for the board.
#
# Included (not prepended) because nothing here overrides a core method — every
# name is new. Where a core method genuinely needs wrapping we use prepend and
# super, or UnboundMethod capture for helpers other plugins alias.
module RedmineExpertAgile
  module Patches
    module IssuePatch
      def self.apply!
        return if Issue.included_modules.include?(self)

        Issue.include(self)
      end

      def self.included(base)
        base.class_eval do
          has_one :expert_agile_data, :dependent => :destroy, :foreign_key => 'issue_id'
          has_one :expert_agile_sprint, :through => :expert_agile_data, :source => :sprint

          accepts_nested_attributes_for :expert_agile_data, :update_only => true

          # Ordering for the board. Unranked issues go last with a stable
          # tiebreaker, and the NULLS handling is written out because MySQL and
          # PostgreSQL disagree on where NULLs sort by default.
          scope :sorted_by_rank, lambda {
            eager_load(:expert_agile_data).order(
              Arel.sql("CASE WHEN #{ExpertAgileData.table_name}.position IS NULL THEN 1 ELSE 0 END ASC"),
              Arel.sql("#{ExpertAgileData.table_name}.position ASC"),
              Arel.sql("#{Issue.table_name}.id ASC")
            )
          }

          safe_attributes 'expert_agile_data_attributes',
                          :if => lambda { |issue, user|
                            issue.new_record? || user.allowed_to?(:edit_issues, issue.project)
                          }

          # Named expert_agile_card_color rather than 'color': the attribute
          # goes through safe_attributes into a shared namespace, and
          # redmine_agile already ships an agile_color_attributes of its own.
          safe_attributes 'expert_agile_card_color',
                          :if => lambda { |issue, user|
                            issue.new_record? || user.allowed_to?(:edit_issues, issue.project)
                          }
        end
      end

      # The association row is created on demand, so callers never have to care
      # whether it exists yet.
      def expert_agile_data!
        expert_agile_data || build_expert_agile_data
      end

      def story_points
        expert_agile_data&.story_points
      end

      def story_points=(value)
        expert_agile_data!.story_points = value.presence
      end

      # Story points of this issue plus every descendant, which is what a parent
      # card should show. Returns nil when nothing in the subtree is estimated,
      # so the UI can distinguish "no estimate" from "estimated as zero".
      def total_story_points
        # SUM over zero rows is NULL, so `pick` distinguishes "nothing in this
        # subtree is estimated" (nil) from "the subtree sums to 0" in a single
        # query. `sum` would flatten both to 0.
        ExpertAgileData.where(:issue_id => self_and_descendants.select(:id))
                       .pick(Arel.sql('SUM(story_points)'))
      end

      # Whether the story point field applies to this issue at all.
      def story_points_available?
        RedmineExpertAgile.story_points_for_tracker?(tracker)
      end

      def expert_agile_card_color
        color
      end

      def expert_agile_card_color=(value)
        self.color = value
      end
    end
  end
end
