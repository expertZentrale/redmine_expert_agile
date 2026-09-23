require File.expand_path('../../test_helper', __FILE__)

class ExpertAgileColorTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles,
           :enabled_modules, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :issues

  def setup
    @issue = Issue.find(1)
    User.current = User.find(1)
  end

  def teardown
    User.current = nil
    ExpertAgileColor.delete_all
  end

  # --- Model -----------------------------------------------------------

  def test_color_must_be_a_hex_value
    %w(chartreuse blue #12345 #gggggg javascript:alert(1)).each do |value|
      record = ExpertAgileColor.new(:container => Tracker.first, :color => value)

      assert_not record.valid?, "#{value.inspect} must not be accepted"
      assert record.errors[:color].any?
    end
  end

  def test_any_hex_colour_is_accepted_and_normalised
    record = ExpertAgileColor.new(:container => Tracker.first, :color => ' #3D7EC4 ')
    assert record.valid?
    assert_equal '#3d7ec4', record.color

    record.color = '#abc'
    assert_equal '#aabbcc', record.color
    record.color = '123abc'
    assert_equal '#123abc', record.color
  end

  def test_normalize_rejects_what_is_not_a_colour
    assert_equal '#3d7ec4', ExpertAgileColor.normalize('#3D7EC4')
    assert_nil ExpertAgileColor.normalize('blue')
    assert_nil ExpertAgileColor.normalize('#3d7ec4ff'), 'no alpha: a card colour is opaque'
    assert_nil ExpertAgileColor.normalize(nil)
    assert_nil ExpertAgileColor.normalize(['#3d7ec4'])
  end

  # The card's text sits on the tint, so the tint has to stay light for any
  # pick — black included. The accent only ever colours a border.
  def test_the_tint_stays_light_enough_to_read_dark_text_on
    ['#000000', '#1a1a2e', '#cc3b3b', '#ffffff', '#00ff00'].each do |hex|
      tint = ExpertAgileColor.tint(hex, ExpertAgileColor::CARD_TINT)
      channels = tint.delete('#').scan(/../).map { |pair| pair.to_i(16) }

      assert channels.min >= 230, "#{hex} tints to #{tint}, too dark behind card text"
    end
  end

  def test_tint_matches_the_shades_the_palette_used_to_hard_code
    # Two of the values expert_agile.css used to carry by hand for the palette.
    # Those were tuned by eye, so close is the promise, not identical.
    { '#3d7ec4' => '#f2f7fd', '#cc3b3b' => '#fdf3f3' }.each do |hex, old|
      tint = ExpertAgileColor.tint(hex, ExpertAgileColor::CARD_TINT)
      channels = [tint, old].map { |c| c.delete('#').scan(/../).map { |pair| pair.to_i(16) } }

      assert channels[0].zip(channels[1]).all? { |a, b| (a - b).abs <= 3 },
             "#{hex} tints to #{tint}, a visible change from the #{old} cards had"
    end
  end

  def test_css_variables_carry_accent_and_tint
    css = ExpertAgileColor.css_variables('#3d7ec4', ExpertAgileColor::CARD_TINT)
    tint = ExpertAgileColor.tint('#3d7ec4', ExpertAgileColor::CARD_TINT)

    assert_equal "--ea-accent: #3d7ec4; --ea-tint: #{tint};", css
    assert_nil ExpertAgileColor.css_variables(nil, ExpertAgileColor::CARD_TINT)
    assert_nil ExpertAgileColor.css_variables('red; background: url(x)', ExpertAgileColor::CARD_TINT),
               'only a normalised hex may reach a style attribute'
  end

  def test_container_type_must_be_whitelisted
    record = ExpertAgileColor.new(:color => '#3c9c3c')
    record.container_type = 'User'
    record.container_id = 1

    assert_not record.valid?, 'only whitelisted container types may be coloured'
  end

  def test_one_color_per_container
    ExpertAgileColor.create!(:container => Tracker.first, :color => '#3c9c3c')
    duplicate = ExpertAgileColor.new(:container => Tracker.first, :color => '#cc3b3b')

    assert_not duplicate.valid?
  end

  def test_container_class_resolves_only_whitelisted_names
    assert_equal Tracker, ExpertAgileColor.container_class('tracker')
    assert_equal IssuePriority, ExpertAgileColor.container_class('issue_priority')

    # The admin screen takes this from the URL. Anything outside the whitelist
    # must resolve to nil rather than being constantized.
    assert_nil ExpertAgileColor.container_class('user')
    assert_nil ExpertAgileColor.container_class('enumeration')
    assert_nil ExpertAgileColor.container_class('ActiveRecord::Base')
    assert_nil ExpertAgileColor.container_class('File')
    assert_nil ExpertAgileColor.container_class('')
  end

  # --- Colorable concern ------------------------------------------------

  def test_colorable_is_not_mixed_into_every_model
    # The concern goes only into the models that can be coloured. Mixing it into
    # ActiveRecord::Base (what RedmineUP does) would give every model in the
    # instance an expert_agile_color association.
    assert Tracker.included_modules.include?(RedmineExpertAgile::Colorable)
    assert Project.included_modules.include?(RedmineExpertAgile::Colorable)
    # Issue used to be in this list, back when a card could be coloured one
    # issue at a time.
    assert_not Issue.included_modules.include?(RedmineExpertAgile::Colorable)
    assert_not User.included_modules.include?(RedmineExpertAgile::Colorable)
    assert_not TimeEntry.included_modules.include?(RedmineExpertAgile::Colorable)
    assert_not ActiveRecord::Base.included_modules.include?(RedmineExpertAgile::Colorable)
  end

  def test_setting_and_clearing_a_color
    tracker = Tracker.first

    tracker.color = '#3d7ec4'
    assert_equal '#3d7ec4', tracker.reload.color

    tracker.color = nil
    assert_nil tracker.reload.color
    assert_equal 0, ExpertAgileColor.where(:container_type => 'Tracker',
                                           :container_id => tracker.id).count
  end

  def test_destroying_the_container_destroys_its_color
    tracker = Tracker.create!(:name => 'Throwaway', :default_status_id => IssueStatus.first.id)
    tracker.color = '#cc3b3b'
    assert_equal 1, ExpertAgileColor.where(:container_type => 'Tracker', :container_id => tracker.id).count

    tracker.destroy

    assert_equal 0, ExpertAgileColor.where(:container_type => 'Tracker', :container_id => tracker.id).count
  end

  # --- Card colour resolution -------------------------------------------

  def test_card_color_by_tracker
    @issue.tracker.color = '#8a5fbf'

    assert_equal '#8a5fbf', RedmineExpertAgile::CardColor.for(@issue, 'tracker')
  end

  def test_card_color_by_priority_and_status
    @issue.priority.color = '#e08a1e'
    @issue.status.color = '#123abc'

    assert_equal '#e08a1e', RedmineExpertAgile::CardColor.for(@issue, 'priority')
    assert_equal '#123abc', RedmineExpertAgile::CardColor.for(@issue, 'status'),
                 'a colour off the palette is kept as picked'
  end

  # Dropped on purpose, so the wiring cannot come back by accident: an issue is
  # not something a board colours by, and no colour reaches it any more.
  def test_an_issue_is_not_something_to_colour
    assert_not_includes ExpertAgileColor::COLORABLE_CLASSES.values, 'Issue'
    assert_not_includes ExpertAgileColor::CONTAINER_TYPES, 'Issue'
    assert_not_includes RedmineExpertAgile::COLOR_BASES, 'issue'
    assert_not Issue.new.respond_to?(:expert_agile_card_color)
    assert_nil RedmineExpertAgile::CardColor.for(@issue, 'issue')
  end

  def test_card_color_none_and_missing_issue
    assert_nil RedmineExpertAgile::CardColor.for(@issue, 'none')
    assert_nil RedmineExpertAgile::CardColor.for(nil, 'tracker')
  end

  def test_swatches_are_the_palette_in_hue_order
    assert_equal ExpertAgileColor::PALETTE.values, ExpertAgileColor::SWATCHES
    assert ExpertAgileColor::SWATCHES.all? { |hex| hex.match?(ExpertAgileColor::HEX) }
  end

  # The migration hard-codes the old names so it keeps meaning the same thing;
  # when it was written, those were exactly the palette.
  def test_the_hex_migration_covers_the_whole_old_palette
    require File.expand_path('../../../db/migrate/005_store_card_colors_as_hex', __FILE__)

    assert_equal ExpertAgileColor::PALETTE, StoreCardColorsAsHex::NAMES
  end

  def test_uncoloured_container_falls_back_to_a_stable_palette_entry
    # An unconfigured board still has to be readable. Without a fallback,
    # switching "colour by" to Tracker does nothing until an admin has coloured
    # every tracker by hand, which reads as a broken feature.
    first = RedmineExpertAgile::CardColor.for(@issue, 'tracker')

    assert_includes ExpertAgileColor::SWATCHES, first
    assert_equal first, RedmineExpertAgile::CardColor.for(@issue, 'tracker'),
                 'the fallback must be stable, not random'
  end

  def test_explicit_colour_wins_over_the_fallback
    fallback = RedmineExpertAgile::CardColor.for(@issue, 'tracker')
    explicit = (ExpertAgileColor::SWATCHES - [fallback]).first
    @issue.tracker.color = explicit

    assert_equal explicit, RedmineExpertAgile::CardColor.for(@issue, 'tracker')
  end

  def test_assignee_color_is_deterministic_and_from_the_palette
    user = User.find(2)
    @issue.assigned_to = user

    first = RedmineExpertAgile::CardColor.for(@issue, 'assignee')
    second = RedmineExpertAgile::CardColor.for(@issue, 'assignee')

    assert_equal first, second, 'the same person always gets the same colour'
    # Deriving a hex value from the login, as RedmineUP does, can land on
    # near-white or near-black; drawing from the palette cannot.
    assert_includes ExpertAgileColor::SWATCHES, first
  end

  def test_assignee_color_is_nil_when_unassigned
    @issue.assigned_to = nil

    assert_nil RedmineExpertAgile::CardColor.for(@issue, 'assignee')
  end

  def test_spent_time_color_buckets
    palette = ExpertAgileColor::PALETTE
    assert_equal palette['green'], ExpertAgileColor.for_spent_time(10, 1)
    assert_equal palette['light_green'], ExpertAgileColor.for_spent_time(10, 6)
    assert_equal palette['yellow'], ExpertAgileColor.for_spent_time(10, 9)
    assert_equal palette['orange'], ExpertAgileColor.for_spent_time(10, 11)
    assert_equal palette['red'], ExpertAgileColor.for_spent_time(10, 20)
  end

  def test_spent_time_color_needs_an_estimate
    assert_nil ExpertAgileColor.for_spent_time(nil, 5)
    assert_nil ExpertAgileColor.for_spent_time(0, 5)
  end

  def test_preload_returns_colors_without_per_card_queries
    @issue.tracker.color = '#3c9c3c'
    issues = [@issue]

    map = RedmineExpertAgile::CardColor.preload(issues, 'tracker')

    assert_equal '#3c9c3c', map[@issue.tracker_id]
  end
end
