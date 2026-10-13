# The board's "Epic" column: a card field and a swimlane field at once.
#
# Its value is not an attribute of the issue but the nearest epic above it in
# the subtask tree, which the query answers for the whole board in one go.
# The column therefore holds on to its query and asks it, instead of each card
# walking up its own ancestors.
#
# QueryColumn is defined inside app/models/query.rb, which Zeitwerk loads only
# for the constant Query; naming Query first makes QueryColumn exist whatever
# has been loaded when init.rb requires this file.
Query

module RedmineExpertAgile
  class EpicQueryColumn < QueryColumn
    def initialize(query)
      super(:epic, :sortable => false, :groupable => RedmineExpertAgile::Epics.nearest_epic_sql,
                   :caption => :label_expert_agile_epic)
      @query = query
    end

    def value_object(issue)
      @query.epic_of(issue)
    end

    def value(issue)
      value_object(issue)
    end
  end
end
