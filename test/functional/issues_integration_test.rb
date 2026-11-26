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
  include Redmine::I18n

  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :enabled_modules, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :issues, :issue_categories, :versions,
           :workflows, :journals, :journal_details, :queries

  def setup
    @project = Project.find(1)
    @project.enable_module!(:expert_agile)
    @project.enable_module!(:expert_agile_backlog)
    Role.find(1).add_permission!(:view_expert_agile_board, :edit_expert_agile_board,
                                 :manage_expert_agile_sprints, :manage_expert_agile_backlog)
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

  # The board sends the context menu's field entries itself and redraws from
  # the page it is redirected to. That depends on the board's own address
  # passing as a back_url — for one card the entries update the issue, for
  # several they go to bulk_update.
  def test_an_update_from_the_board_context_menu_returns_to_the_board
    board = "/projects/#{@project.identifier}/expert_agile/board?set_filter=1"
    patch :update, :params => { :id => @issue.id, :ids => [@issue.id], :issue => { :priority_id => 6 },
                                :back_url => board }

    assert_redirected_to board
    assert_equal 6, @issue.reload.priority_id
  end

  def test_bulk_update_from_the_board_context_menu_returns_to_the_board
    board = "/projects/#{@project.identifier}/expert_agile/board?set_filter=1"
    patch :bulk_update, :params => { :ids => [@issue.id], :issue => { :priority_id => 6 },
                                     :back_url => board }

    assert_redirected_to board
    assert_equal 6, @issue.reload.priority_id
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

  # The new-issue form posts expert_agile_data_attributes as soon as the story
  # points or sprint field is shown - even left empty. The nested record used
  # to validate issue_id before the issue had one, so every such create failed
  # with "Issue cannot be blank" (#48).
  def test_create_with_empty_agile_fields
    with_agile_settings('sprints_on' => '1', 'story_points_on' => '1') do
      assert_difference 'Issue.count', 1 do
        post :create, :params => {
          :project_id => @project.id,
          :issue => { :tracker_id => 1, :subject => 'Created from the form',
                      :expert_agile_data_attributes => { :story_points => '', :sprint_id => '' } }
        }
      end
    end

    assert_response :redirect
  end

  def test_create_with_story_points_and_sprint
    own = ExpertAgileSprint.create!(:project => @project, :name => 'Own sprint',
                                    :start_date => Date.new(2026, 1, 1),
                                    :end_date => Date.new(2026, 1, 14))

    with_agile_settings('sprints_on' => '1', 'story_points_on' => '1') do
      post :create, :params => {
        :project_id => @project.id,
        :issue => { :tracker_id => 1, :subject => 'Planned from the start',
                    :expert_agile_data_attributes => { :story_points => '5', :sprint_id => own.id.to_s } }
      }
    end

    assert_response :redirect
    data = Issue.order(:id => :desc).first.expert_agile_data
    assert_equal 5, data.story_points
    assert_equal own.id, data.sprint_id
  end

  # Still enforced on create: the sprint must belong to the new issue's project.
  def test_create_refuses_a_sprint_of_an_unrelated_project
    foreign = foreign_sprint

    with_agile_settings('sprints_on' => '1') do
      assert_no_difference 'Issue.count' do
        post :create, :params => {
          :project_id => @project.id,
          :issue => { :tracker_id => 1, :subject => 'Sneaky',
                      :expert_agile_data_attributes => { :sprint_id => foreign.id.to_s } }
        }
      end
    end

    assert_response :success
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


  # The epic progress row goes through the same hook as the story points.
  def test_an_epic_shows_its_progress_in_its_attribute_table
    epic = Issue.generate!(:project => @project, :tracker_id => 2)
    Issue.generate!(:project => @project, :tracker_id => 1, :parent_issue_id => epic.id)

    with_agile_settings('epic_tracker_ids' => ['2']) do
      get :show, :params => { :id => epic.id }
    end

    assert_response :success
    assert_select '.expert-agile-epic-progress .ea-epic-progress'
    assert_select '.expert-agile-epic-progress-detail',
                  :text => l(:label_expert_agile_epic_progress_issues, :closed => 0, :total => 1)
    # Redmine 5 serves plugin_assets/<plugin>/stylesheets/expert_agile.css,
    # 6 and later a digested expert_agile-<hash>.css.
    hrefs = css_select('link[rel=stylesheet]').map { |link| link['href'] }
    assert hrefs.any? { |href| href =~ %r{redmine_expert_agile/.*expert_agile[-.].*css} }, hrefs.inspect
  end

  def test_an_ordinary_issue_shows_no_epic_progress
    with_agile_settings('epic_tracker_ids' => ['2']) do
      get :show, :params => { :id => @issue.id }
    end

    assert_response :success
    assert_select '.expert-agile-epic-progress', false
  end


  # The sidebar's "Epics and stories" list, followed: the epic tree's data
  # and assets come with it.
  def test_the_epic_tree_list_names_its_epics
    epic = Issue.generate!(:project => @project, :tracker_id => 2, :subject => 'Epic on the list')
    story = Issue.generate!(:project => @project, :tracker_id => 1, :parent_issue_id => epic.id)

    params = RedmineExpertAgile::IssueTree.tree_list_params.merge(:project_id => @project.id, :per_page => 100)
    with_agile_settings('epic_tracker_ids' => ['2']) do
      get :index, :params => params
    end

    assert_response :success
    assert_select 'table.issues tr#issue-' + story.id.to_s + '.idnt-1'
    data = JSON.parse(css_select('script#ea-issue-tree-data').first.text)
    assert_equal l(:label_expert_agile_epic_progress_issues, :closed => 0, :total => 1),
                 data['epics'][epic.id.to_s]['progress']
    assert_equal epic.id.to_s, data['members'][story.id.to_s]
    scripts = css_select('script[src]').map { |script| script['src'] }
    assert scripts.any? { |src| src =~ %r{redmine_expert_agile/.*expert_agile_issue_tree[-.].*js} }, scripts.inspect
    sheets = css_select('link[rel=stylesheet]').map { |link| link['href'] }
    assert sheets.any? { |href| href =~ %r{redmine_expert_agile/.*expert_agile_issue_tree[-.].*css} }, sheets.inspect
  end

  def test_an_issue_list_in_another_order_gets_no_epic_tree
    with_agile_settings('epic_tracker_ids' => ['2']) do
      get :index, :params => { :project_id => @project.id, :set_filter => '1', :sort => 'id:desc' }
    end

    assert_response :success
    assert_select 'script#ea-issue-tree-data', 0
  end

  def test_a_grouped_issue_list_gets_no_epic_tree
    with_agile_settings('epic_tracker_ids' => ['2']) do
      get :index, :params => { :project_id => @project.id, :set_filter => '1', :sort => 'parent',
                               :group_by => 'tracker' }
    end

    assert_response :success
    assert_select 'script#ea-issue-tree-data', 0
  end

  def test_without_epic_trackers_the_issue_list_gets_no_epic_tree
    get :index, :params => { :project_id => @project.id, :set_filter => '1', :sort => 'parent' }

    assert_response :success
    assert_select 'script#ea-issue-tree-data', 0
  end

  def test_the_issue_sidebar_offers_the_epic_tree_where_the_project_plans_with_epics
    with_agile_settings('epic_tracker_ids' => ['2']) do
      get :index, :params => { :project_id => @project.id }
    end

    assert_response :success
    assert_select '#sidebar ul.expert-agile-epic-views a[href*="sort=parent"]',
                  :text => l(:label_expert_agile_epic_view_tree)
  end

  def test_the_issue_sidebar_offers_no_epic_tree_without_the_agile_modules
    @project.disable_module!(:expert_agile)
    @project.disable_module!(:expert_agile_backlog)

    with_agile_settings('epic_tracker_ids' => ['2']) do
      get :index, :params => { :project_id => @project.id }
    end

    assert_response :success
    assert_select '.expert-agile-epic-views', 0
  end

  # The epic picker on the issue form: its row, data and assets where the
  # project plans with epics. The script draws it; core's form stays intact.
  def test_the_new_issue_form_offers_the_epic_picker
    epic = Issue.generate!(:project => @project, :tracker_id => 2, :subject => 'Epic for the form')

    with_agile_settings('epic_tracker_ids' => ['2']) do
      get :new, :params => { :project_id => @project.id, :issue => { :tracker_id => 1 } }
    end

    assert_response :success
    assert_select 'form#issue-form p#ea-epic-picker[hidden] label#ea-epic-picker-label',
                  :text => l(:label_expert_agile_epic)
    assert_select 'form#issue-form input#issue_parent_issue_id'
    data = JSON.parse(css_select('script#ea-epic-picker-data').first.text)
    assert_includes data['epics'].map { |entry| entry['id'] }, epic.id.to_s
    assert_nil data['current']
    assert_epic_picker_assets
  end

  def test_the_edit_form_of_a_story_has_its_epic_chosen
    epic = Issue.generate!(:project => @project, :tracker_id => 2)
    story = Issue.generate!(:project => @project, :tracker_id => 1, :parent_issue_id => epic.id)

    with_agile_settings('epic_tracker_ids' => ['2']) do
      get :edit, :params => { :id => story.id }
    end

    assert_response :success
    assert_equal epic.id.to_s, JSON.parse(css_select('script#ea-epic-picker-data').first.text)['current']
  end

  # Core redraws the form whenever the parent task changes, and the picker
  # comes back with it: here only showing the epic of the story chosen.
  def test_the_redrawn_form_shows_the_epic_through_a_story
    epic = Issue.generate!(:project => @project, :tracker_id => 2)
    story = Issue.generate!(:project => @project, :tracker_id => 1, :parent_issue_id => epic.id)

    with_agile_settings('epic_tracker_ids' => ['2']) do
      post :new, :params => { :project_id => @project.id, :issue => { :tracker_id => 1, :parent_issue_id => story.id } },
                 :format => 'js', :xhr => true
    end

    assert_response :success
    assert_includes response.body, 'ea-epic-picker-data'
    assert_match(/via\\?":\\?"#{story.id}\\?"/, response.body)
  end

  # No picker on an epic, but its assets: switching the tracker to a story
  # redraws the form without loading the page again.
  def test_an_epic_form_has_no_picker_but_its_assets
    with_agile_settings('epic_tracker_ids' => ['2']) do
      get :new, :params => { :project_id => @project.id, :issue => { :tracker_id => 2 } }
    end

    assert_response :success
    assert_select '#ea-epic-picker', 0
    assert_epic_picker_assets
  end

  def test_without_epics_the_issue_form_is_cores
    get :new, :params => { :project_id => @project.id, :issue => { :tracker_id => 1 } }

    assert_response :success
    assert_select '#ea-epic-picker', 0
    scripts = css_select('script[src]').map { |script| script['src'] }
    assert scripts.none? { |src| src.include?('expert_agile_epic_picker') }, scripts.inspect
  end

  # The issue list with the sprint filter and column: a core page, so it is
  # rendered here like every other page the plugin touches.
  def test_the_issue_list_filters_and_shows_the_sprint
    sprint = ExpertAgileSprint.create!(:project => @project, :name => 'Sprint Liste',
                                       :start_date => Date.new(2026, 1, 1), :end_date => Date.new(2026, 1, 14))
    @issue.expert_agile_data!.update!(:sprint_id => sprint.id)

    get :index, :params => { :project_id => @project.id, :set_filter => '1',
                             :f => ['expert_agile_sprint_id'], :op => { 'expert_agile_sprint_id' => '=' },
                             :v => { 'expert_agile_sprint_id' => [sprint.id.to_s] },
                             :c => %w(subject expert_agile_sprint) }

    assert_response :success
    assert_select 'table.issues tr.issue', 1
    assert_select 'table.issues td.expert_agile_sprint', :text => 'Sprint Liste'
  end

  def test_the_issue_list_exports_the_sprint_to_csv
    sprint = ExpertAgileSprint.create!(:project => @project, :name => 'Sprint CSV',
                                       :start_date => Date.new(2026, 1, 1), :end_date => Date.new(2026, 1, 14))
    @issue.expert_agile_data!.update!(:sprint_id => sprint.id)

    get :index, :params => { :project_id => @project.id, :set_filter => '1', :format => 'csv',
                             :c => %w(subject expert_agile_sprint) }

    assert_response :success
    assert_includes response.body, 'Sprint CSV'
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

  # Redmine 5 serves plugin_assets/<plugin>/..., 6 and later digested names.
  def assert_epic_picker_assets
    scripts = css_select('script[src]').map { |script| script['src'] }
    assert scripts.any? { |src| src =~ %r{redmine_expert_agile/.*expert_agile_epic_picker[-.].*js} }, scripts.inspect
    sheets = css_select('link[rel=stylesheet]').map { |link| link['href'] }
    assert sheets.any? { |href| href =~ %r{redmine_expert_agile/.*expert_agile_epic_picker[-.].*css} }, sheets.inspect
  end
end
