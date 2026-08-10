# Sprint associations on Project.
#
# A plain include: every method here is new, so there is nothing to collide
# with and no need for UnboundMethod capture.
module RedmineExpertAgile
  module Patches
    module ProjectPatch
      def self.apply!
        return if Project.included_modules.include?(self)

        Project.include(self)
      end

      def self.included(base)
        base.class_eval do
          has_many :expert_agile_sprints, :dependent => :destroy
        end
      end

      # Every sprint this project may plan into: its own, plus any shared with
      # it from elsewhere in the tree.
      #
      # The inverse of ExpertAgileSprint#shared_projects, expressed as one
      # query with bound parameters rather than a chain of interpolated OR
      # clauses.
      def shared_expert_agile_sprints
        table = ExpertAgileSprint.table_name
        # Project is an awesome_nested_set with lft/rgt and no root_id column,
        # so "same tree" is the root's nested-set span.
        tree_root = root
        ExpertAgileSprint.joins(:project).where(
          "#{table}.project_id = :project_id" \
          " OR #{table}.sharing = :system" \
          " OR (#{table}.sharing = :tree" \
          "     AND projects.lft >= :root_lft AND projects.rgt <= :root_rgt)" \
          " OR (#{table}.sharing = :hierarchy AND (" \
          "     (projects.lft < :lft AND projects.rgt > :rgt)" \
          "  OR (projects.lft > :lft AND projects.rgt < :rgt)))" \
          " OR (#{table}.sharing = :descendants" \
          "     AND projects.lft < :lft AND projects.rgt > :rgt)",
          :project_id => id,
          :system => ExpertAgileSprint::SHARING_SYSTEM,
          :tree => ExpertAgileSprint::SHARING_TREE,
          :hierarchy => ExpertAgileSprint::SHARING_HIERARCHY,
          :descendants => ExpertAgileSprint::SHARING_DESCENDANTS,
          :root_lft => tree_root.lft, :root_rgt => tree_root.rgt,
          :lft => lft, :rgt => rgt
        )
      end

      def active_expert_agile_sprint
        expert_agile_sprints.active.first
      end

      def expert_agile_sprints_any?
        expert_agile_sprints.exists?
      end
    end
  end
end
