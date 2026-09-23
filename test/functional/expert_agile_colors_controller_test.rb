require File.expand_path('../../test_helper', __FILE__)

# The administration screen for card colours.
#
# The point of the tests here is the form: one hex field per container, which
# Coloris turns into a picker offering the palette as swatches, and what it
# posts has to stay what the controller reads — #rrggbb per container, or an
# empty value to clear one.
class ExpertAgileColorsControllerTest < Redmine::ControllerTest
  tests ExpertAgileColorsController

  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :issue_statuses, :enumerations

  def setup
    @request.session[:user_id] = 1
  end

  def teardown
    ExpertAgileColor.delete_all
  end

  def test_index_renders_one_hex_field_per_container
    get :index, :params => { :container_type => 'tracker' }

    assert_response :success
    Tracker.all.each do |tracker|
      assert_select 'input.ea-color-input[type=text][name=?][id=?]',
                    "colors[#{tracker.id}]", "colors_#{tracker.id}"
    end
  end

  # The field carries no text of its own, so without this it is announced as a
  # nameless input and the row it belongs to is lost.
  def test_each_field_is_named_after_what_it_colours
    get :index, :params => { :container_type => 'tracker' }

    assert_response :success
    Tracker.all.each do |tracker|
      assert_select 'input.ea-color-input[aria-label$=?]', tracker.to_s
    end
  end

  def test_index_shows_the_colour_a_container_already_has
    tracker = Tracker.first
    ExpertAgileColor.create!(:container => tracker, :color => '#123abc')

    get :index, :params => { :container_type => 'tracker' }

    assert_response :success
    assert_select 'input.ea-color-input[name=?][value=?]', "colors[#{tracker.id}]", '#123abc'
  end

  # The picker is configured from a data attribute, not inline script: the
  # palette as swatches, and its labels in the user's language.
  def test_index_hands_the_palette_to_the_picker_as_swatches
    get :index, :params => { :container_type => 'tracker' }

    assert_response :success
    form = css_select('form[data-ea-coloris]').first
    assert form, 'the form must carry the picker configuration'
    config = JSON.parse(form['data-ea-coloris'])
    assert_equal ExpertAgileColor::SWATCHES, config['swatches']
    assert config['clearLabel'].present?
    assert config['a11y'].values.all?(&:present?), 'every picker label needs a translation'
  end

  def test_index_loads_coloris_and_the_plugin_assets
    get :index, :params => { :container_type => 'tracker' }

    assert_response :success
    assert_select 'head link[rel=stylesheet][href*=?]', 'coloris.min'
    assert_select 'head link[rel=stylesheet][href*=?]', 'expert_agile'
    assert_select 'head script[src*=?]', 'coloris.min'
    assert_select 'head script[src*=?]', 'expert_agile_colors'
  end

  def test_update_stores_what_the_picker_posts
    tracker = Tracker.first

    put :update, :params => { :container_type => 'tracker',
                              :colors => { tracker.id.to_s => '#E0715E' } }

    assert_redirected_to expert_agile_colors_path(:container_type => 'tracker')
    assert_equal '#e0715e', tracker.reload.color
    assert flash[:notice].present?
  end

  def test_update_clears_a_colour_when_none_is_picked
    tracker = Tracker.first
    ExpertAgileColor.create!(:container => tracker, :color => '#e0715e')

    put :update, :params => { :container_type => 'tracker',
                              :colors => { tracker.id.to_s => '' } }

    assert_redirected_to expert_agile_colors_path(:container_type => 'tracker')
    assert_nil tracker.reload.color
  end

  # The field is free text under the picker: a typo must not be dropped
  # silently, and must not cost the rows that were fine.
  def test_update_names_an_invalid_colour_and_keeps_the_valid_ones
    good, bad = Tracker.first(2)
    ExpertAgileColor.create!(:container => bad, :color => '#3c9c3c')

    put :update, :params => { :container_type => 'tracker',
                              :colors => { good.id.to_s => '#123abc', bad.id.to_s => 'bleu' } }

    assert_redirected_to expert_agile_colors_path(:container_type => 'tracker')
    assert_equal '#123abc', good.reload.color
    assert_equal '#3c9c3c', bad.reload.color, 'a refused colour leaves the old one in place'
    assert_includes flash[:error], bad.to_s
    assert_nil flash[:notice]
  end

  def test_index_requires_an_administrator
    @request.session[:user_id] = 2

    get :index, :params => { :container_type => 'tracker' }

    assert_response :forbidden
  end
end
