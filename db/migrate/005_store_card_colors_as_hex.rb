# Card colours were palette names ('blue'); they are now stored as #rrggbb so
# any colour can be picked. Converts every stored name to the hex it stood for.
#
# The mapping is spelled out here rather than read from ExpertAgileColor: a
# migration has to mean the same thing forever, and the model's palette is free
# to change after this has run.
class StoreCardColorsAsHex < ActiveRecord::Migration[6.1]
  NAMES = {
    'dark_green'   => '#2f7d55',
    'green'        => '#3c9c3c',
    'light_green'  => '#8dc63f',
    'olive'        => '#7f8c34',
    'turquoise'    => '#29a8a0',
    'light_blue'   => '#3fa5d8',
    'blue'         => '#3d7ec4',
    'indigo'       => '#4257b2',
    'purple'       => '#8a5fbf',
    'light_purple' => '#a98cd9',
    'pink'         => '#d1489b',
    'red'          => '#cc3b3b',
    'salmon'       => '#e0715e',
    'orange'       => '#e08a1e',
    'brown'        => '#9c6b42',
    'yellow'       => '#dcb800',
    'slate'        => '#64748b',
    'gray'         => '#8c8c8c'
  }.freeze

  def up
    NAMES.each do |name, hex|
      execute("UPDATE expert_agile_colors SET color = #{quote(hex)} WHERE color = #{quote(name)}")
    end
    # Anything that was neither a palette name nor a colour could never have
    # rendered; drop it rather than carry an invalid row forward.
    execute("DELETE FROM expert_agile_colors WHERE color IS NULL OR color NOT LIKE '#%'")
  end

  # Back to names where a colour is exactly one of the old palette entries.
  # A colour picked freely has no name to go back to, and the old code would
  # reject it, so it is removed.
  def down
    NAMES.each do |name, hex|
      execute("UPDATE expert_agile_colors SET color = #{quote(name)} WHERE color = #{quote(hex)}")
    end
    execute("DELETE FROM expert_agile_colors WHERE color LIKE '#%'")
  end

  private

  def quote(value)
    connection.quote(value)
  end
end
