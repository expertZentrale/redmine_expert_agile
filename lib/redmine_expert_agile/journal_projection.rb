# Reconstructs the historical state of a set of issues from their journals.
#
# This is the part of a chart engine that decides whether charts are usable at
# scale. RedmineUP's cumulative flow chart eager-loads every journal and journal
# detail for the whole scope, then, for every date in the period and every
# issue, re-filters and re-sorts that issue's details inside the inner loop —
# O(dates x issues x journals), with the sort in the innermost position. It is
# why they impose a 1000-item cap (which, as shipped, checks chart names that no
# longer exist and so never actually fires).
#
# Here the journals are read once, in one query, and projected in a single pass
# into a per-issue timeline of checkpoints. Answering "what was issue X on day
# D" is then a binary search — O(journals) to build, O(log n) per lookup.
module RedmineExpertAgile
  class JournalProjection
    # State of one issue at a point in time.
    Snapshot = Struct.new(:status_id, :done_ratio, :closed)

    TRACKED_KEYS = %w(status_id done_ratio).freeze

    # `issues` must be loaded (their current state is the end of the timeline).
    def initialize(issues)
      @issues = Array(issues)
      @by_id = @issues.index_by(&:id)
      @closed_status_ids = IssueStatus.where(:is_closed => true).pluck(:id).to_set
      build_timelines
    end

    def issue_ids
      @by_id.keys
    end

    # State of one issue at the end of `date`, or nil if it did not exist yet.
    def state_of(issue_id, date)
      issue = @by_id[issue_id]
      return nil if issue.nil?
      return nil if local_date(issue.created_on) > date

      checkpoints = @timelines[issue_id]
      return initial_snapshot(issue) if checkpoints.nil? || checkpoints.empty?

      index = last_index_at_or_before(checkpoints, date)
      return initial_snapshot(issue) if index.nil?

      checkpoints[index][1]
    end

    # Issues that existed on `date`, with their state, as {issue_id => Snapshot}.
    def states_on(date)
      result = {}
      @by_id.each_key do |id|
        snapshot = state_of(id, date)
        result[id] = snapshot if snapshot
      end
      result
    end

    def open_on(date)
      states_on(date).reject { |_id, snapshot| snapshot.closed }
    end

    def closed_on(date)
      states_on(date).select { |_id, snapshot| snapshot.closed }
    end

    private

    # Timestamps are stored in UTC but a chart's x axis is days as the reader
    # experiences them. Without this conversion an event at 00:30 local time
    # lands on the previous day for anyone east of UTC, and the whole chart is
    # off by one. Redmine's own date grouping uses the same helper.
    def local_date(time)
      return nil if time.nil?

      if User.current.respond_to?(:time_to_date)
        User.current.time_to_date(time)
      else
        time.to_date
      end
    end

    def closed?(status_id)
      @closed_status_ids.include?(status_id.to_i)
    end

    def initial_snapshot(issue)
      @initial[issue.id] ||= begin
        status_id = @first_old_values.dig(issue.id, 'status_id') || issue.status_id
        done_ratio = @first_old_values.dig(issue.id, 'done_ratio') || issue.done_ratio
        Snapshot.new(status_id.to_i, done_ratio.to_i, closed?(status_id))
      end
    end

    # One query for the whole scope, ordered so the projection is a single
    # forward pass with no per-issue sorting.
    def build_timelines
      @timelines = {}
      @initial = {}
      @first_old_values = {}
      return if @by_id.empty?

      rows = JournalDetail
             .joins(:journal)
             .where(:journals => { :journalized_type => 'Issue', :journalized_id => @by_id.keys })
             .where(:property => 'attr', :prop_key => TRACKED_KEYS)
             .order("#{Journal.table_name}.journalized_id ASC, #{Journal.table_name}.created_on ASC," \
                    " #{JournalDetail.table_name}.id ASC")
             .pluck(Arel.sql("#{Journal.table_name}.journalized_id"),
                    Arel.sql("#{Journal.table_name}.created_on"),
                    :prop_key, :old_value, :value)

      current = {}
      rows.each do |issue_id, created_on, prop_key, old_value, value|
        issue = @by_id[issue_id]
        next if issue.nil?

        # The first change of each kind tells us the state the issue started in.
        @first_old_values[issue_id] ||= {}
        @first_old_values[issue_id][prop_key] = old_value unless @first_old_values[issue_id].key?(prop_key)

        state = current[issue_id] ||= begin
          seed = initial_snapshot(issue)
          Snapshot.new(seed.status_id, seed.done_ratio, seed.closed)
        end

        if prop_key == 'status_id'
          state.status_id = value.to_i
          state.closed = closed?(value)
        else
          state.done_ratio = value.to_i
        end

        date = local_date(created_on)
        checkpoints = (@timelines[issue_id] ||= [])
        snapshot = Snapshot.new(state.status_id, state.done_ratio, state.closed)
        if checkpoints.last && checkpoints.last[0] == date
          # Several changes on one day collapse to that day's final state.
          checkpoints[-1] = [date, snapshot]
        else
          checkpoints << [date, snapshot]
        end
      end
    end

    # Index of the last checkpoint on or before `date`, or nil.
    def last_index_at_or_before(checkpoints, date)
      low = 0
      high = checkpoints.size - 1
      found = nil
      while low <= high
        mid = (low + high) / 2
        if checkpoints[mid][0] <= date
          found = mid
          low = mid + 1
        else
          high = mid - 1
        end
      end
      found
    end
  end
end
