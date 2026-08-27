require File.expand_path('../../test_helper', __FILE__)

# The plugin's view hooks fire on Redmine's own issue pages, so a mistake in
# one takes down a core page rather than a plugin page.
#
# That is exactly what happened: a hook called a predicate that was never
# defined, and every issue page 500'd from the moment sprints landed until a
# user clicked a card. Nothing caught it because no test had ever rendered a
# core page with the plugin loaded. These do.
class IssuesIntegrationTest < Redmine::ControllerTest
  tests IssuesController

  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :enabled_modules, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :issues, :issue_categories, :versions,
           :workflows, :journals, :journal_details, :queries

  def setup
    @project = Project.find(1)
    @project.enable_module!(:expert_agile)
    Role.find(1).add_permission!(:view_expert_agile_board, :edit_expert_agile_board,
                                 :manage_expert_agile_sprints)
    @issue = Issue.find(1)
    @request.session[:user_id] = 2
  end

  def teardown
    ExpertAgileData.delete_all
    ExpertAgileSprint.delete_all
  end

  def test_issue_show_renders
    get :show, :params => { :id => @issue.id }

    assert_response :success
  end

  def test_issue_show_renders_with_story_points_enabled
    with_agile_settings('story_points_on' => '1') do
      @issue.story_points = 5
      @issue.save!

      get :show, :params => { :id => @issue.id }

      assert_response :success
    end
  end

  def test_issue_edit_form_renders
    get :edit, :params => { :id => @issue.id }

    assert_response :success
  end

  # Cards are coloured by what an issue *is* — its tracker, status, priority,
  # project, assignee — never one issue at a time. Nothing colour-shaped
  # belongs on an issue page any more: no field, and none of the assets that
  # used to be loaded for it on every issue page there is.
  def test_issue_pages_carry_nothing_of_the_colour_picker
    get :edit, :params => { :id => @issue.id }

    assert_response :success
    assert_select 'div.ea-color-choice', false
    assert_select 'head link[rel=stylesheet][href*=?]', 'expert_agile', false
    assert_select 'head script[src*=?]', 'expert_agile_colors', false
  end

  def test_issue_edit_form_renders_with_sprints_enabled
    # The regression: the sprint hook's guard did not exist.
    with_agile_settings('sprints_on' => '1', 'story_points_on' => '1') do
      ExpertAgileSprint.create!(:project => @project, :name => 'Sprint A',
                                :start_date => Date.new(2026, 1, 1),
                                :end_date => Date.new(2026, 1, 14))

      get :edit, :params => { :id => @issue.id }

      assert_response :success
    end
  end

  def test_issue_edit_form_renders_with_sprints_enabled_but_none_defined
    with_agile_settings('sprints_on' => '1') do
      get :edit, :params => { :id => @issue.id }

      assert_response :success
    end
  end

  def test_issue_pages_render_with_the_module_disabled
    @project.disable_module!(:expert_agile)

    get :show, :params => { :id => @issue.id }
    assert_response :success

    get :edit, :params => { :id => @issue.id }
    assert_response :success
  end

  def test_new_issue_form_renders
    get :new, :params => { :project_id => @project.id }

    assert_response :success
  end

  def test_issue_list_renders
    get :index, :params => { :project_id => @project.id }

    assert_response :success
  end

  def test_bulk_edit_form_renders
    get :bulk_edit, :params => { :ids => [@issue.id, Issue.find(2).id] }

    assert_response :success
  end

  def test_context_menu_renders
    get :index, :params => { :project_id => @project.id }
    assert_response :success
  end
end
