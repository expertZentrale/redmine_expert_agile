require 'bigdecimal'

# Fractional ranking for board cards.
#
# A move reports only the dragged card and the two cards it landed between; the
# new rank is the midpoint of its neighbours and exactly one row is written.
#
# This is the deliberate departure from RedmineUP, where the browser re-indexes
# a whole column to 0..n-1 and PUTs the entire map, and the server writes one
# row per card. That design has two defects this one does not:
#
#   * Two people dragging in the same column at the same time overwrite each
#     other's ranks — every row is rewritten from a snapshot the client took
#     before the other move landed.
#   * Only rendered cards are in the payload, so dragging inside a column that
#     is paginated (`issues_per_column`) silently reorders the dragged card
#     against every card below the fold.
#
# Midpoints eventually exhaust the available precision, so a column whose
# neighbour gap has collapsed is re-spread before the move is retried. With
# decimal(30,15) and a STEP of 1024 that takes roughly 50 consecutive drops
# into the same gap, so rebalancing is rare.
module RedmineExpertAgile
  class BoardPositions
    # Distance between freshly assigned ranks, and the gap left at either end.
    STEP = BigDecimal('1024')
    # Below this the midpoint stops being representable in decimal(30,15).
    MIN_GAP = BigDecimal('0.000000001')

    class << self
      # Places `issue` between `prev_issue` and `next_issue` and returns the
      # assigned rank.
      #
      # `siblings` is the ordered scope of the destination column, used only if
      # the gap has collapsed and the column has to be re-spread.
      def place!(issue, prev_issue: nil, next_issue: nil, siblings: nil)
        ExpertAgileData.transaction do
          before = position_of(prev_issue)
          after = position_of(next_issue)
          rank = midpoint(before, after)

          if rank.nil?
            # The neighbours are adjacent at full precision. Re-spread the
            # column, then re-read the neighbours and try once more.
            rebalance!(siblings) if siblings
            before = position_of(reload_data(prev_issue))
            after = position_of(reload_data(next_issue))
            rank = midpoint(before, after)
            raise ArgumentError, 'unable to allocate a board position' if rank.nil?
          end

          data = issue.expert_agile_data || issue.build_expert_agile_data
          data.position = rank
          data.save!
          rank
        end
      end

      # The rank for a card appended to the end of a column.
      def append_position(siblings)
        last = maximum_position(siblings)
        last ? last + STEP : STEP
      end

      # Re-spreads an ordered collection of issues onto clean, evenly separated
      # ranks. Only called when midpoints run out of room.
      def rebalance!(siblings)
        issues = Array(siblings.respond_to?(:to_a) ? siblings.to_a : siblings)
        return if issues.empty?

        ExpertAgileData.transaction do
          issues.each_with_index do |issue, index|
            data = issue.expert_agile_data || issue.build_expert_agile_data
            data.position = STEP * (index + 1)
            data.save!
          end
        end
      end

      private

      # nil means "there is no room between these two".
      def midpoint(before, after)
        return STEP if before.nil? && after.nil?
        # Dropped at the top: leave a full step of headroom below the first card
        # so later drops above it do not immediately collapse.
        return after - STEP if before.nil?
        return before + STEP if after.nil?
        return nil if after - before < MIN_GAP

        (before + after) / 2
      end

      def position_of(issue)
        return nil if issue.nil?

        value = issue.expert_agile_data && issue.expert_agile_data.position
        value && BigDecimal(value.to_s)
      end

      def reload_data(issue)
        return nil if issue.nil?

        issue.association(:expert_agile_data).reload
        issue
      end

      def maximum_position(siblings)
        return nil if siblings.nil?

        ids = siblings.respond_to?(:map) ? siblings.map { |i| i.respond_to?(:id) ? i.id : i } : []
        return nil if ids.empty?

        value = ExpertAgileData.where(:issue_id => ids).maximum(:position)
        value && BigDecimal(value.to_s)
      end
    end
  end
end
