# Per-issue card colours were dropped, so the rows holding them are now
# unreachable: nothing reads them, nothing can write them, and no screen offers
# Issue as something to colour. They are deleted rather than left in the table,
# where they would keep a unique index entry per issue for a feature that no
# longer exists.
#
# Written as SQL rather than through the model on purpose: a migration has to
# keep working against whatever the model looks like later, and this one names
# a container type the model no longer knows about.
class DeleteIssueCardColors < ActiveRecord::Migration[6.1]
  def up
    execute("DELETE FROM expert_agile_colors WHERE container_type = 'Issue'")
  end

  # Deliberately not an IrreversibleMigration: rolling every migration back is
  # how the plugin is uninstalled, and refusing here would leave that stuck.
  # The colours cannot come back either way — nothing recorded them elsewhere.
  def down; end
end
