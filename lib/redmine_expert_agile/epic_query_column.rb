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
      super(:epic, :sortable => false, :groupable => true, :caption => :label_expert_agile_epic)
      @query = query
    end

    # Core groups in SQL by the column's name, which is no column of the
    # issues table. The board groups its loaded cards in Ruby and never asks;
    # anything grouping in the database counts by the nearest epic's id, which
    # IssueQueryPatch turns back into the epic `group_value` answers with.
    def group_by_statement
      RedmineExpertAgile::Epics.nearest_epic_sql
    end

    def group_records(ids)
      Issue.where(:id => ids).index_by(&:id)
    end

    def value_object(issue)
      @query.epic_of(issue)
    end

    def value(issue)
      value_object(issue)
    end
  end
end
