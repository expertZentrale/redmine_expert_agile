# Builds the two-dimensional board: swimlanes down, status columns across.
#
# Lives in lib/ rather than under app/models/expert_agile_query/ so it can be
# required explicitly. Defining it as a constant nested inside the model would
# make Zeitwerk autoload it while ExpertAgileQuery is still being defined — a
# load cycle that only shows up at boot.
#
# Everything here derives from ONE loaded set of issues. `group_by_statement`
# deliberately is not used for SQL: for an association column it returns the
# bare column name ("tracker"), which is a Ruby-side grouping key, not a SQL
# expression — feeding it to `group()` produces "Unknown column 'tracker'".
module RedmineExpertAgile
  module BoardGrid
    # The issues on the board: filtered, rank-ordered and capped. Loaded once
    # and reused by the grid, the swimlanes and the totals.
    def board_issues
      @board_issues ||= begin
        limit = RedmineExpertAgile.board_items_limit
        scope = board_scope.sorted_by_rank
        @truncated = scope.except(:order, :limit).count > limit
        scope.limit(limit).to_a
      end
    end

    # Whether the board hit its item cap, so the view can say so instead of
    # silently showing a partial board.
    def truncated?
      board_issues
      @truncated.present?
    end

    # The swimlanes to render, with a trailing nil lane for issues that have no
    # value for the grouped field.
    #
    # Derived from the loaded issues, so a lane only appears when it actually
    # holds a card, and no extra query is needed.
    def swimlanes
      return [] unless grouped?

      @swimlanes ||= begin
        column = group_by_column
        values = board_issues.map { |issue| column.group_value(issue) }
        lanes = sort_lanes(values.compact.uniq)
        lanes << nil if values.any?(&:nil?)
        lanes
      end
    end

    # The board grid: {[status_id, swimlane_key] => [issues]} when grouped,
    # {[status_id] => [issues]} otherwise. Cells keep the rank order they were
    # loaded in.
    def issue_board
      @issue_board ||= begin
        column = grouped? ? group_by_column : nil
        board_issues.group_by do |issue|
          if column
            [issue.status_id, lane_key(column.group_value(issue))]
          else
            [issue.status_id]
          end
        end
      end
    end

    # Issues of one cell. Pass :none for an ungrouped board, or a swimlane
    # (including nil, the "no value" lane) for a grouped one.
    def issues_for(status_id, swimlane = :none)
      key = swimlane == :none ? [status_id] : [status_id, lane_key(swimlane)]
      issue_board[key] || []
    end

    private

    # Association lanes are identified by id; a scalar grouped value is its own
    # key. nil stays nil, which is the "no value" lane.
    def lane_key(value)
      value.respond_to?(:id) ? value.id : value
    end

    # Redmine's own ordering where the lane object has one (trackers, statuses
    # and priorities carry `position`), otherwise alphabetical.
    def sort_lanes(lanes)
      if lanes.all? { |lane| lane.respond_to?(:position) && lane.position.present? }
        lanes.sort_by(&:position)
      else
        lanes.sort_by { |lane| lane.to_s.downcase }
      end
    end
  end
end
