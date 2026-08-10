# Per-issue agile payload: board rank, story points and sprint assignment.
#
# One row per issue (has_one from Issue), created lazily on first use.
#
# `position` is a decimal, not an integer, on purpose. RedmineUP stores dense
# integers and lets the browser re-index a whole column on every drop, which
# corrupts ordering under concurrent drags and silently reorders against cards
# that are paginated out of view. A fractional rank lets the server write a
# single row per move: the new position is the midpoint between the two
# neighbours the client reports. RedmineExpertAgile::BoardPositions rebalances a
# column when the gap between neighbours gets too small to halve meaningfully.
#
# Pinned to ActiveRecord::Migration[6.1] for Redmine 5.0 compatibility.
class CreateExpertAgileData < ActiveRecord::Migration[6.1]
  def change
    create_table :expert_agile_data do |t|
      t.integer :issue_id, :null => false
      t.decimal :position, :precision => 30, :scale => 15
      t.integer :story_points
      t.integer :sprint_id
    end

    # has_one assumes uniqueness — enforce it in the schema rather than trusting
    # callers (the RedmineUP table has no such constraint).
    add_index :expert_agile_data, :issue_id, :unique => true, :name => 'index_expert_agile_data_on_issue_id'
    add_index :expert_agile_data, :position, :name => 'index_expert_agile_data_on_position'
    # Declared explicitly: `add_column ..., :index => true` is silently ignored
    # by Rails, which is why the RedmineUP equivalents of these columns ended up
    # with no index at all.
    add_index :expert_agile_data, :sprint_id, :name => 'index_expert_agile_data_on_sprint_id'
  end
end
