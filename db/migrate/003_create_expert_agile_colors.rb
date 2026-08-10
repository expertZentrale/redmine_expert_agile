# Card colours, attached polymorphically to whatever the board colours by:
# Issue, Project, Tracker, IssuePriority or IssueStatus.
#
# One composite index on (container_type, container_id) rather than two
# single-column indexes — every lookup filters on both, and the type alone is
# hopelessly low-cardinality.
class CreateExpertAgileColors < ActiveRecord::Migration[6.1]
  def change
    create_table :expert_agile_colors do |t|
      t.integer :container_id
      t.string  :container_type
      t.string  :color
    end

    add_index :expert_agile_colors, [:container_type, :container_id],
              :unique => true, :name => 'index_expert_agile_colors_on_container'
  end
end
