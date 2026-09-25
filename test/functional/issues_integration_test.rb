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
    assert_select 'input.ea-color-input', false
    assert_select 'head script[src*=?]', 'coloris', false
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

  # --- Sprints of other projects --------------------------------------

  # The form offers only the sprints this project may plan into, but the value
  # is whatever the request says. A crafted id of another project's sprint used
  # to be saved, and the issue history then printed that sprint's name, so any
  # sprint name in the instance could be read by walking the ids.
  def test_update_refuses_a_sprint_of_an_unrelated_project
    foreign = foreign_sprint

    put :update, :params => {
      :id => @issue.id,
      :issue => { :expert_agile_data_attributes => { :sprint_id => foreign.id.to_s } }
    }

    assert_response :success # the form again, with the error
    assert_select '#errorExplanation'
    assert_nil ExpertAgileData.where(:issue_id => @issue.id).pick(:sprint_id)
  end

  def test_update_accepts_a_sprint_of_the_issues_project
    own = ExpertAgileSprint.create!(:project => @project, :name => 'Own sprint',
                                    :start_date => Date.new(2026, 1, 1),
                                    :end_date => Date.new(2026, 1, 14))

    put :update, :params => {
      :id => @issue.id,
      :issue => { :expert_agile_data_attributes => { :sprint_id => own.id.to_s } }
    }

    assert_response :redirect
    assert_equal own.id, ExpertAgileData.where(:issue_id => @issue.id).pick(:sprint_id)
  end

  # Journals written before the validation may still point at a sprint the
  # reader has no business knowing about. The history names it only when the
  # reader could see it anyway, and shows the bare id otherwise.
  def test_history_does_not_name_a_sprint_the_reader_cannot_see
    foreign = foreign_sprint
    journal_sprint_change(foreign)

    get :show, :params => { :id => @issue.id }

    assert_response :success
    assert_not_includes response.body, foreign.name
  end

  def test_history_names_a_sprint_of_the_issues_project
    own = ExpertAgileSprint.create!(:project => @project, :name => 'Own sprint',
                                    :start_date => Date.new(2026, 1, 1),
                                    :end_date => Date.new(2026, 1, 14))
    journal_sprint_change(own)

    get :show, :params => { :id => @issue.id }

    assert_response :success
    assert_includes response.body, own.name
  end

  private

  # A sprint of project 2, which user 2 cannot see a board of and which shares
  # nothing with project 1.
  def foreign_sprint
    ExpertAgileSprint.create!(:project => Project.find(2), :name => 'Confidential sprint',
                              :start_date => Date.new(2026, 1, 1),
                              :end_date => Date.new(2026, 1, 14))
  end

  def journal_sprint_change(sprint)
    journal = Journal.create!(:journalized => @issue, :user => User.find(1), :notes => 'Planned')
    JournalDetail.create!(:journal => journal, :property => 'attr',
                          :prop_key => 'expert_agile_sprint_id', :value => sprint.id.to_s)
  end
end
