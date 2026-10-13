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
    # A sprint the reader may not have named to them: still its own group,
    # under a neutral label, rather than folded into the issues without one.
    # Equal by id, so every row of that sprint lands in the same group.
    HiddenSprint = Struct.new(:id) do
      def to_s
        ::I18n.t(:label_expert_agile_sprint_unavailable)
      end
    end

    def self.sprint_sql(column)
      "(SELECT eas.#{column} FROM #{ExpertAgileSprint.table_name} eas " \
        "INNER JOIN #{ExpertAgileData.table_name} ead ON ead.sprint_id = eas.id " \
        "WHERE ead.issue_id = #{Issue.table_name}.id)"
    end

    def initialize(query)
      @query = query
      # Start date first, then the sprint itself: two sprints starting the
      # same day must not interleave, or a grouped list repeats its headers.
      super(:expert_agile_sprint, :sortable => [self.class.sprint_sql('start_date'), self.class.sprint_sql('id')],
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
      shown(self.class.sprint_of(issue))
    end

    # The counted group keys as the records `group_value` answers with.
    def group_records(ids)
      sprints = ExpertAgileSprint.where(:id => ids).index_by(&:id)
      ids.each_with_object({}) { |id, records| records[id.to_i] = shown(sprints[id.to_i]) || HiddenSprint.new(id.to_i) }
    end

    def value_object(issue)
      sprint = group_value(issue)
      sprint && sprint.to_s
    end

    # Core's default would read the association straight off the issue and
    # skip the name check.
    def value(issue)
      value_object(issue)
    end

    private

    # The sprint as the reader may see it. An issue can keep a sprint its
    # project has since stopped sharing — the assignment is checked only when
    # it changes — and the issue history withholds such a sprint's name; so
    # does the list. A name is shown where the reader may see the sprint's
    # board, or where the list's project may plan into it.
    def shown(sprint)
      return nil if sprint.nil?

      nameable_sprint_ids.include?(sprint.id) ? sprint : HiddenSprint.new(sprint.id)
    end

    # One query per list, not one per row.
    def nameable_sprint_ids
      @nameable_sprint_ids ||= begin
        ids = ExpertAgileSprint.visible.pluck(:id)
        ids += @query.project.shared_expert_agile_sprints.pluck(:id) if @query && @query.project
        ids.to_set
      end
    end
  end
end
