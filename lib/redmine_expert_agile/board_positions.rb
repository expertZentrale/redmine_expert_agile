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
#
# Ranks are created lazily — an issue nobody has dragged has no row at all and
# sorts, with the rest of the unranked cards, after the ranked ones in id order.
# That means a midpoint is not always available: a card dropped between two
# never-moved cards has to sit inside a run that is ordered by id, where no
# number fits. Those cards are given real ranks first, down to the drop point
# only, and the move proceeds as usual.
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
      # `siblings` is the ordered scope of the destination column. It is read
      # when a neighbour has never been ranked, and re-spread when the gap
      # between two ranks has collapsed.
      def place!(issue, prev_issue: nil, next_issue: nil, siblings: nil)
        ExpertAgileData.transaction do
          # A neighbour that was never dragged carries no rank to sit next to.
          # Unranked cards trail the column in id order and no number sorts
          # *inside* that tail, so the cards above the drop point are given real
          # ranks first, in the order they are already displayed in.
          #
          # Without this a drop between two never-moved cards was placed as if
          # the column were empty, and the card jumped to the top instead. The
          # column that consists entirely of such cards is the one issues are
          # created in — "New" — where reordering therefore never held.
          column = materialize_ranks_above!(issue, prev_issue, siblings) if unranked?(prev_issue)

          before = position_of(prev_issue)
          after = position_of(next_issue)
          rank = place_between(before, after, siblings, column)

          if rank.nil?
            # The neighbours are adjacent at full precision. Re-spread the
            # column, then re-read the neighbours and try once more.
            rebalance!(siblings) if siblings
            before = position_of(reload_data(prev_issue))
            after = position_of(reload_data(next_issue))
            rank = place_between(before, after, siblings, nil)
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
        end_position(ordered_ids(siblings))
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

      # The rank for a drop, or nil when there is no room between the
      # neighbours. `column` is the ordered id list if one was already read.
      def place_between(before, after, siblings, column)
        return midpoint(before, after) unless after.nil?

        # Nothing ranked below the drop point: the card belongs at the end of
        # the column's ranked run, still above the unranked tail. Measured
        # against the whole column rather than `before + STEP`, so two cards
        # dropped into the same spot cannot land on the same rank.
        end_position(column || ordered_ids(siblings), before)
      end

      # nil means "there is no room between these two".
      def midpoint(before, after)
        # Dropped at the top: leave a full step of headroom below the first card
        # so later drops above it do not immediately collapse.
        return after - STEP if before.nil?
        return nil if after - before < MIN_GAP

        (before + after) / 2
      end

      # Gives every card from the top of the column down to `boundary` a real
      # rank, keeping the order they are displayed in and writing only the rows
      # that need a number. Cards below the drop point are neither read nor
      # written, so the work is bounded by where the card was dropped rather
      # than by the size of the column. Returns the ids it read, which always
      # include every ranked card in the column.
      def materialize_ranks_above!(issue, boundary, siblings)
        return [] if siblings.nil?

        ids = ordered_ids(above(siblings, boundary))
        # `boundary` is missing when it is not part of this column at all — a
        # neighbour the client reported from a board that has moved on. Nothing
        # to place it against, so nothing is rewritten.
        return ids unless ids.include?(boundary.id)

        # The moved card is skipped: it is leaving this slot anyway, and the
        # backlog planner passes a sibling scope that still contains it.
        prefix = ids - [issue.id]
        rows = ExpertAgileData.where(:issue_id => prefix).index_by(&:issue_id)
        last = nil

        prefix.each do |id|
          row = rows[id]
          current = row && row.position && BigDecimal(row.position.to_s)
          # An existing rank is kept as long as it still increases. Equal ranks
          # — two cards once dropped into the same spot — are re-spread.
          if current && (last.nil? || current > last)
            last = current
            next
          end

          last = last.nil? ? STEP : last + STEP
          row ||= ExpertAgileData.new(:issue_id => id)
          row.position = last
          row.save!
        end

        reload_data(boundary)
        ids
      end

      # Above every rank in `ids`, and above `before`.
      def end_position(ids, before = nil)
        highest = [maximum_position(ids), before].compact.max
        highest ? highest + STEP : STEP
      end

      def unranked?(issue)
        !issue.nil? && position_of(issue).nil?
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

      # The part of a column that sorts above `boundary`, which is only ever
      # asked for an unranked card. Ranked cards all come first, and the
      # unranked tail behind them is ordered by id (see `sorted_by_rank`), so
      # that is every ranked card plus every unranked id up to the boundary's
      # own. Written as a condition rather than a slice off the full id list to
      # keep a drop near the top of a long column from reading all of it.
      def above(siblings, boundary)
        siblings.where(
          "#{ExpertAgileData.table_name}.position IS NOT NULL OR #{Issue.table_name}.id <= ?",
          boundary.id
        )
      end

      # Ids in board order. Plucked rather than loaded: the column can hold
      # thousands of issues and none of them is needed as an object here.
      def ordered_ids(siblings)
        return [] if siblings.nil?

        (siblings.respond_to?(:pluck) ? siblings.pluck(:id) : Array(siblings).map(&:id)).uniq
      end

      def maximum_position(ids)
        return nil if ids.blank?

        value = ExpertAgileData.where(:issue_id => ids).maximum(:position)
        value && BigDecimal(value.to_s)
      end
    end
  end
end
