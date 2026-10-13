# The issue list's "Sprint" column: shows, sorts and groups by the sprint an
# issue is planned into.
#
# The value is the sprint's name, not the sprint record, and that is what the
# column groups by in SQL as well. Redmine counts the issues of each group with
# one GROUP BY over `group_by_statement` and then looks every row's group up by
# its `group_value`; both sides have to produce the same key, or each group
# header shows no count.
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
    # table here; the sprint's name is.
    def group_by_statement
      self.class.sprint_sql('name')
    end

    def value_object(issue)
      sprint = issue.expert_agile_sprint
      sprint && sprint.name
    end

    def value(issue)
      value_object(issue)
    end
  end
end
