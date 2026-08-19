require File.expand_path('../../test_helper', __FILE__)

# Fractional board ranking.
#
# These are the cases that motivated not copying RedmineUP's dense-integer,
# client-computed scheme: concurrent moves, and moves in a column whose lower
# half is paginated away.
class BoardPositionsTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles,
           :enabled_modules, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :issues

  Positions = RedmineExpertAgile::BoardPositions

  def setup
    @project = Project.find(1)
    User.current = User.find(1)
    @a = Issue.generate!(:project_id => @project.id)
    @b = Issue.generate!(:project_id => @project.id)
    @c = Issue.generate!(:project_id => @project.id)
  end

  def teardown
    User.current = nil
    ExpertAgileData.delete_all
  end

  def rank(issue)
    issue.reload.expert_agile_data.position
  end

  def rank_at(issue, value)
    data = issue.expert_agile_data || issue.build_expert_agile_data
    data.position = value
    data.save!
    issue
  end

  # --- Placement ------------------------------------------------------

  def test_first_card_in_an_empty_column_gets_a_position
    Positions.place!(@a)

    assert_equal Positions::STEP, rank(@a)
  end

  def test_card_dropped_between_two_others_lands_between_them
    rank_at(@a, 100)
    rank_at(@c, 200)

    Positions.place!(@b, :prev_issue => @a, :next_issue => @c)

    assert_equal 150, rank(@b).to_i
    assert_operator rank(@a), :<, rank(@b)
    assert_operator rank(@b), :<, rank(@c)
  end

  def test_card_dropped_at_the_top_sorts_before_everything
    rank_at(@a, 100)

    Positions.place!(@b, :prev_issue => nil, :next_issue => @a)

    assert_operator rank(@b), :<, rank(@a)
  end

  def test_card_dropped_at_the_bottom_sorts_after_everything
    rank_at(@a, 100)

    Positions.place!(@b, :prev_issue => @a, :next_issue => nil)

    assert_operator rank(@b), :>, rank(@a)
  end

  def test_a_move_writes_exactly_one_row
    rank_at(@a, 100)
    rank_at(@c, 200)
    before = ExpertAgileData.order(:issue_id).pluck(:issue_id, :position)

    Positions.place!(@b, :prev_issue => @a, :next_issue => @c)

    after = ExpertAgileData.where(:issue_id => [@a.id, @c.id]).order(:issue_id).pluck(:issue_id, :position)
    assert_equal before, after, 'neighbours must not be rewritten by a move'
  end

  # --- The cases the dense-integer scheme gets wrong ------------------

  def test_two_concurrent_moves_do_not_overwrite_each_other
    # Both clients saw the same column and drop into different gaps. With
    # client-computed dense indices the second PUT would rewrite every row from
    # a stale snapshot and silently undo the first move.
    rank_at(@a, 100)
    rank_at(@b, 200)
    rank_at(@c, 300)
    first = Issue.generate!(:project_id => @project.id)
    second = Issue.generate!(:project_id => @project.id)

    Positions.place!(first, :prev_issue => @a, :next_issue => @b)
    Positions.place!(second, :prev_issue => @b, :next_issue => @c)

    order = [@a, first, @b, second, @c].map { |issue| rank(issue) }
    assert_equal order.sort, order, 'both moves survive, in the intended order'
  end

  def test_moving_within_a_paginated_column_keeps_hidden_cards_in_order
    # Only the first two cards are rendered; the third is below the fold and is
    # therefore absent from anything the client could send.
    rank_at(@a, 100)
    rank_at(@b, 200)
    hidden = rank_at(@c, 300)

    # Drag @b above @a using only what the client can see.
    Positions.place!(@b, :prev_issue => nil, :next_issue => @a)

    assert_operator rank(@b), :<, rank(@a)
    assert_operator rank(@a), :<, rank(hidden),
                   'the unrendered card keeps its place relative to the rest'
  end

  # --- Columns that were never dragged in ------------------------------

  # Every issue starts life unranked, so the column issues are created in —
  # "New" — holds nothing but unranked cards. A drop between two of them used to
  # be ranked as though the column were empty, which sent the card to the top.

  def order_of(*issues)
    Issue.where(:id => issues.map(&:id)).sorted_by_rank.pluck(:id)
  end

  def column_of(*issues)
    Issue.where(:id => issues.map(&:id)).sorted_by_rank
  end

  def test_dropping_between_two_unranked_cards_lands_between_them
    Positions.place!(@c, :prev_issue => @a, :next_issue => @b,
                     :siblings => column_of(@a, @b))

    assert_equal [@a.id, @c.id, @b.id], order_of(@a, @b, @c)
  end

  def test_dropping_below_the_last_unranked_card_lands_at_the_bottom
    Positions.place!(@a, :prev_issue => @c, :next_issue => nil,
                     :siblings => column_of(@b, @c))

    assert_equal [@b.id, @c.id, @a.id], order_of(@a, @b, @c)
  end

  def test_dropping_above_the_first_unranked_card_lands_at_the_top
    Positions.place!(@c, :prev_issue => nil, :next_issue => @a,
                     :siblings => column_of(@a, @b))

    assert_equal [@c.id, @a.id, @b.id], order_of(@a, @b, @c)
  end

  def test_only_the_cards_above_the_drop_point_are_ranked
    # The work a move does is bounded by where the card was dropped, not by the
    # size of the column: a column of thousands of unranked issues must not be
    # rewritten wholesale because one card moved near the top.
    Positions.place!(@c, :prev_issue => @a, :next_issue => @b,
                     :siblings => column_of(@a, @b))

    assert_not_nil @a.reload.expert_agile_data, 'the card above the drop point is ranked'
    assert_nil @b.reload.expert_agile_data, 'the card below it is left alone'
  end

  def test_a_ranked_card_above_the_drop_point_keeps_its_rank
    rank_at(@a, 100)

    Positions.place!(@c, :prev_issue => @b, :next_issue => nil,
                     :siblings => column_of(@a, @b))

    assert_equal BigDecimal('100'), BigDecimal(rank(@a).to_s), 'no needless rewrite'
    assert_equal [@a.id, @b.id, @c.id], order_of(@a, @b, @c)
  end

  def test_two_cards_dropped_at_the_end_of_the_ranked_run_get_distinct_ranks
    # Both land between the last ranked card and the unranked tail. Ranking the
    # second one as `prev + STEP` would put it on the rank the first one took.
    rank_at(@a, 100)
    first = Issue.generate!(:project_id => @project.id)
    second = Issue.generate!(:project_id => @project.id)
    siblings = lambda { |moved| Issue.where(:id => [@a.id, @b.id, first.id, second.id] - [moved.id]).sorted_by_rank }

    Positions.place!(first, :prev_issue => @a, :next_issue => @b, :siblings => siblings.call(first))
    Positions.place!(second, :prev_issue => @a, :next_issue => @b, :siblings => siblings.call(second))

    assert_not_equal rank(first), rank(second)
    assert_equal [@a.id, first.id, second.id, @b.id], order_of(@a, @b, first, second)
  end

  def test_a_card_dragged_down_into_the_unranked_tail_stays_where_it_was_dropped
    rank_at(@a, 100)
    tail = Issue.generate!(:project_id => @project.id)

    # @a is dragged from the top of the column down between @c and tail.
    Positions.place!(@a, :prev_issue => @c, :next_issue => tail,
                     :siblings => Issue.where(:id => [@b.id, @c.id, tail.id]).sorted_by_rank)

    assert_equal [@b.id, @c.id, @a.id, tail.id], order_of(@a, @b, @c, tail)
  end

  # --- Precision and rebalancing --------------------------------------

  def test_repeated_drops_into_a_narrowing_gap_keep_working
    # Each card is dropped directly above the one placed before it, so the gap
    # halves every time. This is the pattern that eventually exhausts precision.
    rank_at(@a, 100)
    rank_at(@c, 101)
    upper = @c
    seen = []

    20.times do
      issue = Issue.generate!(:project_id => @project.id)
      Positions.place!(issue, :prev_issue => @a, :next_issue => upper)
      current = rank(issue)

      assert_operator current, :>, rank(@a)
      assert_operator current, :<, rank(upper)
      assert_not_includes seen, current, 'each drop gets a distinct rank'
      seen << current
      upper = issue
    end
  end

  def test_collapsed_gap_triggers_a_rebalance_and_still_places_the_card
    # Neighbours adjacent at full precision: no midpoint exists.
    rank_at(@a, BigDecimal('1.000000000000001'))
    rank_at(@c, BigDecimal('1.000000000000002'))
    siblings = Issue.where(:id => [@a.id, @c.id]).sorted_by_rank

    Positions.place!(@b, :prev_issue => @a, :next_issue => @c, :siblings => siblings)

    assert_operator rank(@a), :<, rank(@b)
    assert_operator rank(@b), :<, rank(@c)
  end

  def test_rebalance_spreads_a_column_evenly_and_preserves_order
    rank_at(@a, 1)
    rank_at(@b, 2)
    rank_at(@c, 3)

    Positions.rebalance!(Issue.where(:id => [@a.id, @b.id, @c.id]).sorted_by_rank)

    ranks = [@a, @b, @c].map { |issue| rank(issue) }
    assert_equal ranks.sort, ranks
    assert_equal [Positions::STEP, Positions::STEP * 2, Positions::STEP * 3],
                 ranks.map { |r| BigDecimal(r.to_s) }
  end

  def test_append_position_goes_after_the_last_card
    rank_at(@a, 500)

    assert_operator Positions.append_position(Issue.where(:id => @a.id)), :>, 500
  end

  def test_append_position_on_an_empty_column
    assert_equal Positions::STEP, Positions.append_position(Issue.none)
  end
end
