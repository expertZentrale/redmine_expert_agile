# The issue list's "Sprint" column: shows, sorts and groups by the sprint an
# issue is planned into.
#
# Groups by the sprint itself, not by its name: names are unique only within a
# project, and the column is offered on cross-project lists too. Redmine counts
# each group with one GROUP BY over `group_by_statement` (the sprint id here)
# and looks every row's group up by `group_value` (the sprint record);
# IssueQueryPatch turns the counted ids into the same records, see
# `group_records`.
#
# QueryColumn is defined inside app/models/query.rb, which Zeitwerk loads only
# for the constant Query; naming Query first makes QueryColumn exist whatever
# has been loaded when init.rb requires this file.
Query

module RedmineExpertAgile
  class SprintQueryColumn < QueryColumn
    def self.sprint_sql(column)
      "(SELECT eas.#{column} FROM #{ExpertAgileSprint.table_name} eas " \
        "INNER JOIN #{ExpertAgileData.table_name} ead ON ead.sprint_id = eas.id " \
        "WHERE ead.issue_id = #{Issue.table_name}.id)"
    end

    def initialize
      super(:expert_agile_sprint, :sortable => self.class.sprint_sql('start_date'),
                                  :groupable => true,
                                  :caption => :label_expert_agile_sprint)
    end

    # Core groups by the column's name, which is no column of the issues
    # table here.
    def group_by_statement
      "(SELECT ead.sprint_id FROM #{ExpertAgileData.table_name} ead WHERE ead.issue_id = #{Issue.table_name}.id)"
    end

    # Through the agile data row: IssueQueryPatch preloads it with its sprint
    # for the whole page, which a has_one :through would not pick up.
    def self.sprint_of(issue)
      data = issue.expert_agile_data
      data && data.sprint
    end

    def group_value(issue)
      self.class.sprint_of(issue)
    end

    # The counted group keys as the records `group_value` answers with.
    def group_records(ids)
      ExpertAgileSprint.where(:id => ids).index_by(&:id)
    end

    def value_object(issue)
      sprint = self.class.sprint_of(issue)
      sprint && sprint.name
    end

    def value(issue)
      value_object(issue)
    end
  end
end
