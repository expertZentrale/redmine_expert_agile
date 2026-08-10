# Sprints as a first-class entity, independent of Redmine versions.
#
# Versions carry release semantics and have no start date, so a sprint burndown
# would need one stored somewhere regardless. Sprints and versions coexist: the
# backlog planner can plan into either (see ExpertAgileBacklogQuery).
#
# `sharing` mirrors Version#sharing semantics (0 none, 1 descendants,
# 2 hierarchy, 3 tree, 4 system) so a sprint can span a project tree the same
# way a shared version does.
class CreateExpertAgileSprints < ActiveRecord::Migration[6.1]
  def change
    create_table :expert_agile_sprints do |t|
      t.integer :project_id, :null => false
      t.string  :name, :null => false
      t.text    :description
      t.integer :status, :null => false, :default => 0   # 0 open, 1 active, 2 closed
      t.date    :start_date, :null => false
      t.date    :end_date, :null => false
      t.integer :sharing, :null => false, :default => 0
      t.timestamps :null => false
    end

    add_index :expert_agile_sprints, :project_id, :name => 'index_expert_agile_sprints_on_project_id'
    add_index :expert_agile_sprints, :sharing, :name => 'index_expert_agile_sprints_on_sharing'
    add_index :expert_agile_sprints, [:project_id, :name],
              :unique => true, :name => 'index_expert_agile_sprints_on_project_and_name'
  end
end
