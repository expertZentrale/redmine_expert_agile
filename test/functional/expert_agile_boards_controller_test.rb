require File.expand_path('../../test_helper', __FILE__)

class ExpertAgileBoardsControllerTest < Redmine::ControllerTest
  tests ExpertAgileBoardsController
  include Redmine::I18n

  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :enabled_modules, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :issues, :issue_categories, :versions,
           :workflows, :queries

  def setup
    @project = Project.find(1)
    @project.enable_module!(:expert_agile)
    @role = Role.find(1)
    @role.add_permission!(:view_expert_agile_board, :edit_expert_agile_board)
    @issue = Issue.find(1)
    @request.session[:user_id] = 2
  end

  def teardown
    ExpertAgileData.delete_all
  end

  # --- Rendering -------------------------------------------------------

  def test_index_renders_the_board
    get :index, :params => { :project_id => @project.id }

    assert_response :success
    assert_select 'div#ea-board'
    assert_select 'th.ea-column-header'
    assert_select 'div.ea-card'
  end

  def test_index_emits_a_json_island_and_no_inline_script_of_our_own
    get :index, :params => { :project_id => @project.id }

    assert_response :success
    assert_select 'script#ea-board-data[type=?]', 'application/json'
    # Our markup must contain no executable inline script, so the board works
    # under `script-src 'self'`. Redmine's own layout emits inline scripts
    # (importmap, warnLeavingUnsaved), which is outside the plugin's control —
    # so this asserts about the board subtree, not the whole page.
    assert_select 'div#ea-board script', false,
                  'the board must not contain inline <script>'
    assert_select 'div.ea-card script', false,
                  'cards must be markup only — they are re-injected after a move'
    assert_select 'div#ea-board [onclick]', false, 'no inline event handlers'
  end

  # --- Options panel ---------------------------------------------------
  #
  # These go through the controller with real request parameters on purpose.
  # The model-level tests pass plain hashes, which hid that
  # ActionController::Parameters does not implement each_with_object and the
  # whole board 500'd the moment anyone touched a WIP limit.

  def test_index_renders_the_options_panel
    get :index, :params => { :project_id => @project.id }

    assert_response :success
    assert_select 'form#ea_query_form'
    assert_select 'fieldset#filters'
    assert_select 'fieldset#ea-columns-options input[name=?]', 'board_status_ids[]'
    assert_select 'select#color_base'
    assert_select 'input[name=?]', 'show_avatar'
  end

  def test_board_columns_follow_the_selected_statuses
    chosen = IssueStatus.sorted.first(2)

    get :index, :params => { :project_id => @project.id, :set_filter => '1',
                             :board_status_ids => chosen.map { |s| s.id.to_s } }

    assert_response :success
    assert_select 'th.ea-column-header[data-column-id]', :count => chosen.size
    chosen.each do |status|
      assert_select "th.ea-column-header[data-column-id=?] .ea-column-name", status.id.to_s,
                    :text => status.name
    end
  end

  def test_wip_limits_are_applied_from_request_parameters
    status_id = @issue.status_id

    get :index, :params => { :project_id => @project.id, :set_filter => '1',
                             :board_status_ids => [status_id.to_s],
                             :wip_limits => { status_id.to_s => %w(1 2) } }

    assert_response :success
    assert_select "th.ea-column-header[data-column-id=?] .ea-column-wip", status_id.to_s,
                  :text => '1-2'
    # The fixture project has more than two issues in this status, so the limit
    # is breached — and the move must still not be blocked anywhere.
    assert_select 'th.ea-column-header.ea-wip-over'
  end

  def test_applied_options_survive_a_reload
    # The options panel is a GET form, so without session persistence every
    # setting would live only in the URL and vanish the moment the page was
    # reloaded or reached again from the project menu.
    status_id = @issue.status_id
    get :index, :params => { :project_id => @project.id, :set_filter => '1',
                             :board_status_ids => [status_id.to_s],
                             :wip_limits => { status_id.to_s => ['', '5'] },
                             :group_by => 'tracker', :color_base => 'priority',
                             :show_avatar => '0' }
    assert_response :success

    # Same page again, with no parameters at all.
    get :index, :params => { :project_id => @project.id }

    assert_response :success
    assert_select 'th.ea-column-header[data-column-id]', :count => 1
    assert_select "th.ea-column-header[data-column-id=?] .ea-column-wip", status_id.to_s,
                  :text => '5'
    assert_select 'tr.ea-swimlane-title th', :minimum => 1
    assert_select 'img.ea-avatar', false
  end

  def test_session_board_is_scoped_to_its_project
    status_id = @issue.status_id
    get :index, :params => { :project_id => @project.id, :set_filter => '1',
                             :board_status_ids => [status_id.to_s] }
    assert_response :success

    # A different project must not inherit the first project's columns.
    other = Project.find(5)
    other.enable_module!(:expert_agile)
    get :index, :params => { :project_id => other.id }

    assert_response :success
    assert_select 'th.ea-column-header[data-column-id]', :minimum => 1
  end

  def test_swimlanes_are_applied
    get :index, :params => { :project_id => @project.id, :set_filter => '1',
                             :group_by => 'tracker' }

    assert_response :success
    assert_select 'tr.ea-swimlane-title th', :minimum => 1
  end

  def test_swimlane_band_spans_every_column
    # A lane has to read as one band across the board. A narrow label cell on
    # the left leaves the row visually unconnected across the columns.
    get :index, :params => { :project_id => @project.id, :set_filter => '1',
                             :group_by => 'tracker' }

    assert_response :success
    columns = css_select('thead th.ea-column-header[data-column-id]').size
    assert_operator columns, :>, 0
    assert_select 'tr.ea-swimlane-title th' do |cells|
      cells.each do |cell|
        assert_equal columns.to_s, cell['colspan'],
                     'the lane band must span every column'
      end
    end
  end

  def test_swimlane_band_carries_its_own_totals
    get :index, :params => { :project_id => @project.id, :set_filter => '1',
                             :group_by => 'tracker' }

    assert_response :success
    assert_select 'tr.ea-swimlane-title .ea-swimlane-count', :minimum => 1
  end

  def test_swimlanes_are_given_distinguishable_colours
    # Grouping by a field with several values must not paint every lane the
    # same hue, or the bands stop carrying information.
    get :index, :params => { :project_id => @project.id, :set_filter => '1',
                             :group_by => 'priority' }

    assert_response :success
    classes = css_select('tr.ea-swimlane-title').map do |row|
      row['class'].to_s.split.detect { |c| c.start_with?('ea-lane-') }
    end.compact
    assert classes.any?, 'lanes must carry an accent class'
    if classes.size > 1
      assert_operator classes.uniq.size, :>, 1,
                      'adjacent lanes must not all share one colour'
    end
  end

  def test_colour_basis_is_applied
    get :index, :params => { :project_id => @project.id, :set_filter => '1',
                             :color_base => 'priority' }

    assert_response :success
    assert_select 'div.ea-card[class*=?]', 'ea-color-'
  end

  def test_card_fields_come_from_the_query_columns
    get :index, :params => { :project_id => @project.id, :set_filter => '1',
                             :c => %w(status priority) }

    assert_response :success
    assert_select 'dl.ea-card-fields dt', :minimum => 1
  end

  def test_created_and_updated_are_available_as_card_fields
    get :index, :params => { :project_id => @project.id, :set_filter => '1',
                             :c => %w(created_on updated_on) }

    assert_response :success
    assert_select 'dl.ea-card-fields dt', :text => l(:field_created_on), :minimum => 1
    assert_select 'dl.ea-card-fields dt', :text => l(:field_updated_on), :minimum => 1
  end

  def test_time_in_status_card_field
    # Redmine has no such attribute, so this is the board's own column, answered
    # from one grouped journal query rather than a lookup per card.
    issue = Issue.generate!(:project_id => @project.id, :status_id => @issue.status_id)
    journal = Journal.create!(:journalized => issue, :user => User.find(2))
    journal.update_columns(:created_on => 5.days.ago)
    JournalDetail.create!(:journal_id => journal.id, :property => 'attr',
                          :prop_key => 'status_id', :old_value => '1',
                          :value => issue.status_id.to_s)

    get :index, :params => { :project_id => @project.id, :set_filter => '1',
                             :c => %w(day_in_state) }

    assert_response :success
    assert_select 'dl.ea-card-fields dt', :text => l(:label_expert_agile_day_in_state), :minimum => 1
    assert_select "div#ea-card-#{issue.id} dl.ea-card-fields dd", :text => l(:label_expert_agile_days_count, :count => 5)
  end

  def test_time_in_status_falls_back_to_creation_for_untouched_issues
    fresh = Issue.generate!(:project_id => @project.id, :status_id => @issue.status_id)

    get :index, :params => { :project_id => @project.id, :set_filter => '1',
                             :c => %w(day_in_state) }

    assert_response :success
    assert_select "div#ea-card-#{fresh.id} dl.ea-card-fields dd",
                  :text => l(:label_expert_agile_today)
  end

  def test_description_excerpt_is_shown_when_selected
    issue = Issue.generate!(:project_id => @project.id, :status_id => @issue.status_id,
                            :description => 'h1. Heading' + "\n\n" + ('lorem ipsum ' * 60))

    get :index, :params => { :project_id => @project.id, :set_filter => '1',
                             :c => %w(description) }

    assert_response :success
    excerpt = css_select("div#ea-card-#{issue.id} p.ea-card-description").first
    assert_not_nil excerpt, 'the description excerpt must be rendered'
    assert excerpt.text.length <= RedmineExpertAgile.card_description_length + 10,
           'the excerpt must be short'
    # A card is a summary: wiki markup would drag headings and tables into it.
    assert_select "div#ea-card-#{issue.id} p.ea-card-description h1", false
  end

  def test_description_excerpt_strips_html_and_survives_long_tokens
    # Descriptions ingested from email are full of HTML and start with a long
    # unbroken token (an address), which is what makes a whitespace-separated
    # truncation collapse to a few characters.
    long_address = 'sender.with.a.very.long.name@some.extremely.long.example.domain.invalid'
    issue = Issue.generate!(
      :project_id => @project.id, :status_id => @issue.status_id,
      :description => "test2 <img src='x'/> <b>bold</b> Von: #{long_address} " + ('wort ' * 60)
    )

    get :index, :params => { :project_id => @project.id, :set_filter => '1',
                             :c => %w(description) }

    assert_response :success
    excerpt = css_select("div#ea-card-#{issue.id} p.ea-card-description").first.text
    assert_not_includes excerpt, '<img', 'HTML must be stripped, not escaped into view'
    assert_not_includes excerpt, '<b>'
    assert_operator excerpt.length, :>, 60,
                    'a long token must not collapse the excerpt to a few characters'
  end

  def test_description_is_not_shown_unless_selected
    Issue.generate!(:project_id => @project.id, :status_id => @issue.status_id,
                    :description => 'some text')

    get :index, :params => { :project_id => @project.id, :set_filter => '1', :c => %w(tracker) }

    assert_response :success
    assert_select 'p.ea-card-description', false
  end

  def test_description_is_offered_in_the_options_panel
    get :index, :params => { :project_id => @project.id }

    assert_response :success
    assert_select 'fieldset#options input[type=checkbox][name=?][value=?]', 'c[]', 'description'
  end

  def test_avatar_can_be_switched_off
    get :index, :params => { :project_id => @project.id, :set_filter => '1', :show_avatar => '0' }

    assert_response :success
    assert_select 'img.ea-avatar', false
  end

  # --- Sidebar ---------------------------------------------------------

  def test_sidebar_lists_saved_boards_and_the_other_agile_views
    mine = ExpertAgileQuery.create!(:name => 'Mine', :project => @project,
                                    :user => User.find(2),
                                    :visibility => Query::VISIBILITY_PRIVATE)
    shared = ExpertAgileQuery.create!(:name => 'Shared', :project => @project,
                                      :user => User.find(1),
                                      :visibility => Query::VISIBILITY_PUBLIC)

    get :index, :params => { :project_id => @project.id }

    assert_response :success
    assert_select '#sidebar a', :text => mine.name
    assert_select '#sidebar a', :text => shared.name
    assert_select '#sidebar ul.ea-sidebar-nav a', :minimum => 1
  end

  def test_sidebar_does_not_list_chart_queries_among_the_boards
    # ExpertAgileChartsQuery is a subclass, so an unqualified lookup would show
    # saved charts in the boards list.
    ExpertAgileChartsQuery.create!(:name => 'A chart', :project => @project,
                                   :user => User.find(2),
                                   :visibility => Query::VISIBILITY_PUBLIC)

    get :index, :params => { :project_id => @project.id }

    assert_response :success
    assert_select '#sidebar a', { :text => 'A chart', :count => 0 }
  end

  def test_index_requires_the_view_permission
    @role.remove_permission!(:view_expert_agile_board)

    get :index, :params => { :project_id => @project.id }

    assert_response :forbidden
  end

  def test_index_requires_the_module
    @project.disable_module!(:expert_agile)

    get :index, :params => { :project_id => @project.id }

    assert_response :forbidden
  end

  # --- Moving cards ----------------------------------------------------

  def test_update_moves_a_card_to_another_column
    target = allowed_status_for(@issue)
    skip 'workflow offers no other status' if target.nil?

    put :update, :params => { :id => @issue.id, :status_id => target.id }, :format => :js

    assert_response :success
    assert_equal target.id, @issue.reload.status_id
    assert_not_nil @issue.expert_agile_data.position, 'the moved card is ranked'
  end

  def test_update_returns_the_card_and_fresh_column_counts
    target = allowed_status_for(@issue)
    skip 'workflow offers no other status' if target.nil?

    put :update, :params => { :id => @issue.id, :status_id => target.id }, :format => :js
    payload = JSON.parse(response.body)

    assert_equal @issue.id, payload['issueId']
    assert_includes payload['card'], "ea-card-#{@issue.id}"
    assert payload['columns'].is_a?(Array)
  end

  def test_update_rejects_a_status_the_workflow_forbids
    forbidden = forbidden_status_for(@issue)
    original = @issue.status_id
    assert_not_includes @issue.new_statuses_allowed_to(User.find(2)).map(&:id), forbidden.id

    put :update, :params => { :id => @issue.id, :status_id => forbidden.id }, :format => :js

    assert_response :unprocessable_entity
    assert_equal original, @issue.reload.status_id, 'a rejected move changes nothing'
    assert JSON.parse(response.body)['error'].present?
  end

  def test_update_reorders_within_a_column_without_changing_status
    others = 2.times.map do
      Issue.generate!(:project_id => @project.id, :status_id => @issue.status_id)
    end
    others.each_with_index do |issue, index|
      ExpertAgileData.create!(:issue_id => issue.id, :position => (index + 1) * 100)
    end

    put :update, :params => { :id => @issue.id,
                              :prev_id => others[0].id,
                              :next_id => others[1].id }, :format => :js

    assert_response :success
    position = @issue.reload.expert_agile_data.position
    assert_operator position, :>, others[0].reload.expert_agile_data.position
    assert_operator position, :<, others[1].reload.expert_agile_data.position
  end

  def test_update_requires_the_edit_permission
    @role.remove_permission!(:edit_expert_agile_board)

    put :update, :params => { :id => @issue.id }, :format => :js

    assert_response :forbidden
  end

  def test_update_is_rejected_for_an_issue_the_user_cannot_edit
    # Issue#editable? is attributes_editable? OR notes_addable?, so both have to
    # go — dropping :edit_issues alone still leaves the issue "editable".
    @role.remove_permission!(:edit_issues, :add_issue_notes)

    put :update, :params => { :id => @issue.id }, :format => :js

    assert_response :forbidden
    assert JSON.parse(response.body)['error'].present?
  end

  # --- WIP limits ------------------------------------------------------

  def test_wip_limit_does_not_block_a_move
    # Advisory only: the column reports the breach, the move still happens.
    target = allowed_status_for(@issue)
    skip 'workflow offers no other status' if target.nil?
    query = ExpertAgileQuery.new(:name => 'Board', :project => @project)
    query.board_status_ids = [@issue.status_id, target.id]
    query.wip_limits = { target.id => [nil, 0] }
    query.visibility = Query::VISIBILITY_PUBLIC
    query.save!

    put :update, :params => { :id => @issue.id, :status_id => target.id,
                              :query_id => query.id }, :format => :js

    assert_response :success
    assert_equal target.id, @issue.reload.status_id
    moved_column = JSON.parse(response.body)['columns'].detect { |c| c['id'] == target.id }
    assert moved_column['over_wip_limit'], 'the breach is reported back to the board'
  end

  # --- Tooltip ---------------------------------------------------------

  def test_issue_tooltip
    get :issue_tooltip, :params => { :id => @issue.id }

    assert_response :success
    assert_select 'div.ea-tooltip'
  end

  private

  def allowed_status_for(issue)
    issue.new_statuses_allowed_to(User.find(2)).detect { |status| status.id != issue.status_id }
  end

  # A status no workflow transition mentions, so it can never be reached.
  # Picking "some status the role happens not to have" is not deterministic —
  # a Manager role may well be allowed every status in the fixtures, and the
  # test would quietly skip exactly the behaviour it exists to prove.
  def forbidden_status_for(_issue)
    IssueStatus.create!(:name => 'Unreachable by workflow')
  end
end
