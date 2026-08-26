require File.expand_path('../../test_helper', __FILE__)

# The administration screen for card colours.
#
# The point of the tests here is the form: it offers the palette as swatches
# rather than as a list of colour names, and what it posts has to stay what the
# controller reads — a palette name per container, or an empty value to clear
# one.
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

  def test_index_offers_the_whole_palette_as_swatches
    get :index, :params => { :container_type => 'tracker' }

    assert_response :success
    tracker = Tracker.first
    ExpertAgileColor::COLORS.each do |color|
      assert_select "input[type=radio][name=?][value=?]", "colors[#{tracker.id}]", color
      assert_select "span.ea-color-swatch.ea-color-#{color}"
    end
    # Empty value in the selector rather than as a substitution: a trailing
    # string argument is read as the expected element text, not as a message.
    assert_select "input[type=radio][name=?][value='']", "colors[#{tracker.id}]"
  end

  # The swatches carry no text, so without this the group is announced as a
  # nameless set of radio buttons and the row it belongs to is lost.
  def test_each_group_of_swatches_is_named_after_what_it_colours
    get :index, :params => { :container_type => 'tracker' }

    assert_response :success
    Tracker.all.each do |tracker|
      assert_select "div.ea-color-choice[role=radiogroup][aria-label=?]", tracker.to_s
    end
  end

  def test_index_marks_the_colour_a_container_already_has
    tracker = Tracker.first
    ExpertAgileColor.create!(:container => tracker, :color => 'indigo')

    get :index, :params => { :container_type => 'tracker' }

    assert_response :success
    assert_select "input[type=radio][name=?][value=indigo][checked=checked]", "colors[#{tracker.id}]"
  end

  def test_update_stores_what_the_picker_posts
    tracker = Tracker.first

    put :update, :params => { :container_type => 'tracker',
                              :colors => { tracker.id.to_s => 'salmon' } }

    assert_redirected_to expert_agile_colors_path(:container_type => 'tracker')
    assert_equal 'salmon', tracker.reload.color
  end

  def test_update_clears_a_colour_when_none_is_picked
    tracker = Tracker.first
    ExpertAgileColor.create!(:container => tracker, :color => 'salmon')

    put :update, :params => { :container_type => 'tracker',
                              :colors => { tracker.id.to_s => '' } }

    assert_redirected_to expert_agile_colors_path(:container_type => 'tracker')
    assert_nil tracker.reload.color
  end

  def test_index_requires_an_administrator
    @request.session[:user_id] = 2

    get :index, :params => { :container_type => 'tracker' }

    assert_response :forbidden
  end
end
