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

  def test_color_must_come_from_the_palette
    record = ExpertAgileColor.new(:container => Tracker.first, :color => 'chartreuse')

    assert_not record.valid?
    assert record.errors[:color].any?
  end

  def test_container_type_must_be_whitelisted
    record = ExpertAgileColor.new(:color => 'green')
    record.container_type = 'User'
    record.container_id = 1

    assert_not record.valid?, 'only whitelisted container types may be coloured'
  end

  def test_one_color_per_container
    ExpertAgileColor.create!(:container => Tracker.first, :color => 'green')
    duplicate = ExpertAgileColor.new(:container => Tracker.first, :color => 'red')

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
    assert Issue.included_modules.include?(RedmineExpertAgile::Colorable)
    assert Tracker.included_modules.include?(RedmineExpertAgile::Colorable)
    assert_not User.included_modules.include?(RedmineExpertAgile::Colorable)
    assert_not TimeEntry.included_modules.include?(RedmineExpertAgile::Colorable)
    assert_not ActiveRecord::Base.included_modules.include?(RedmineExpertAgile::Colorable)
  end

  def test_setting_and_clearing_a_color
    tracker = Tracker.first

    tracker.color = 'blue'
    assert_equal 'blue', tracker.reload.color

    tracker.color = nil
    assert_nil tracker.reload.color
    assert_equal 0, ExpertAgileColor.where(:container_type => 'Tracker',
                                           :container_id => tracker.id).count
  end

  def test_destroying_the_container_destroys_its_color
    tracker = Tracker.create!(:name => 'Throwaway', :default_status_id => IssueStatus.first.id)
    tracker.color = 'red'
    assert_equal 1, ExpertAgileColor.where(:container_type => 'Tracker', :container_id => tracker.id).count

    tracker.destroy

    assert_equal 0, ExpertAgileColor.where(:container_type => 'Tracker', :container_id => tracker.id).count
  end

  # --- Card colour resolution -------------------------------------------

  def test_card_color_by_tracker
    @issue.tracker.color = 'purple'

    assert_equal 'purple', RedmineExpertAgile::CardColor.for(@issue, 'tracker')
  end

  def test_card_color_by_priority_and_status
    @issue.priority.color = 'orange'
    @issue.status.color = 'blue'

    assert_equal 'orange', RedmineExpertAgile::CardColor.for(@issue, 'priority')
    assert_equal 'blue', RedmineExpertAgile::CardColor.for(@issue, 'status')
  end

  def test_card_color_per_issue
    @issue.color = 'red'

    assert_equal 'red', RedmineExpertAgile::CardColor.for(@issue, 'issue')
  end

  def test_color_set_on_a_new_record_is_persisted_after_save
    # A new issue has no id yet, so the polymorphic row cannot be written until
    # after_save.
    issue = Issue.new(:project_id => 1, :tracker_id => 1, :subject => 'Coloured',
                      :author_id => 1, :status_id => 1, :priority_id => 4)
    issue.safe_attributes = { 'expert_agile_card_color' => 'purple' }

    assert issue.save, issue.errors.full_messages.join(', ')
    assert_equal 'purple', issue.reload.expert_agile_card_color
  end

  def test_color_is_assignable_through_safe_attributes_on_an_existing_issue
    @issue.safe_attributes = { 'expert_agile_card_color' => 'blue' }
    @issue.save!

    assert_equal 'blue', @issue.reload.color
  end

  def test_card_color_none_and_missing_issue
    assert_nil RedmineExpertAgile::CardColor.for(@issue, 'none')
    assert_nil RedmineExpertAgile::CardColor.for(nil, 'tracker')
  end

  # The palette is three things that have to agree: the names, what the picker
  # and the cards paint, and what an admin reads. Adding a colour and forgetting
  # one of them is the obvious way to break it, so all three are pinned here.
  def test_every_palette_colour_is_painted_by_the_stylesheet
    css = File.read(File.expand_path('../../../assets/stylesheets/expert_agile.css', __FILE__))

    ExpertAgileColor::COLORS.each do |color|
      assert_includes css, ".ea-card.ea-color-#{color} ",
                      "#{color} has no card rule"
      assert_includes css, ".ea-color-swatch.ea-color-#{color} ",
                      "#{color} has no swatch rule, so the picker shows it blank"
    end
  end

  def test_every_palette_colour_is_named_in_both_locales
    %i[en de].each do |locale|
      ExpertAgileColor::COLORS.each do |color|
        key = "label_expert_agile_color_#{color}"
        assert I18n.exists?(key, locale), "#{key} is missing from #{locale}.yml"
      end
    end
  end

  def test_uncoloured_container_falls_back_to_a_stable_palette_entry
    # An unconfigured board still has to be readable. Without a fallback,
    # switching "colour by" to Tracker does nothing until an admin has coloured
    # every tracker by hand, which reads as a broken feature.
    first = RedmineExpertAgile::CardColor.for(@issue, 'tracker')

    assert_includes ExpertAgileColor::COLORS, first
    assert_equal first, RedmineExpertAgile::CardColor.for(@issue, 'tracker'),
                 'the fallback must be stable, not random'
  end

  def test_explicit_colour_wins_over_the_fallback
    fallback = RedmineExpertAgile::CardColor.for(@issue, 'tracker')
    explicit = (ExpertAgileColor::COLORS - [fallback]).first
    @issue.tracker.color = explicit

    assert_equal explicit, RedmineExpertAgile::CardColor.for(@issue, 'tracker')
  end

  def test_per_issue_colouring_has_no_fallback
    # Colouring by issue means "only the ones I marked stand out"; a fallback
    # would colour every card and defeat the point.
    assert_nil RedmineExpertAgile::CardColor.for(@issue, 'issue')

    @issue.color = 'red'
    assert_equal 'red', RedmineExpertAgile::CardColor.for(@issue, 'issue')
  end

  def test_assignee_color_is_deterministic_and_from_the_palette
    user = User.find(2)
    @issue.assigned_to = user

    first = RedmineExpertAgile::CardColor.for(@issue, 'assignee')
    second = RedmineExpertAgile::CardColor.for(@issue, 'assignee')

    assert_equal first, second, 'the same person always gets the same colour'
    # Deriving a hex value from the login, as RedmineUP does, can land on
    # near-white or near-black; drawing from the palette cannot.
    assert_includes ExpertAgileColor::COLORS, first
  end

  def test_assignee_color_is_nil_when_unassigned
    @issue.assigned_to = nil

    assert_nil RedmineExpertAgile::CardColor.for(@issue, 'assignee')
  end

  def test_spent_time_color_buckets
    assert_equal 'green', ExpertAgileColor.for_spent_time(10, 1)
    assert_equal 'light_green', ExpertAgileColor.for_spent_time(10, 6)
    assert_equal 'yellow', ExpertAgileColor.for_spent_time(10, 9)
    assert_equal 'orange', ExpertAgileColor.for_spent_time(10, 11)
    assert_equal 'red', ExpertAgileColor.for_spent_time(10, 20)
  end

  def test_spent_time_color_needs_an_estimate
    assert_nil ExpertAgileColor.for_spent_time(nil, 5)
    assert_nil ExpertAgileColor.for_spent_time(0, 5)
  end

  def test_preload_returns_colors_without_per_card_queries
    @issue.tracker.color = 'green'
    issues = [@issue]

    map = RedmineExpertAgile::CardColor.preload(issues, 'tracker')

    assert_equal 'green', map[@issue.tracker_id]
  end
end
