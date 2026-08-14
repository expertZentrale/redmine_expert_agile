# The agile board: rendering it, and moving cards on it.
class ExpertAgileBoardsController < ApplicationController
  menu_item :expert_agile

  before_action :find_project_by_project_id, :only => [:index, :create_issue]
  before_action :find_issue_for_board, :only => [:update, :edit_issue, :update_issue,
                                                 :issue_tooltip, :agile_data, :update_agile_data]
  before_action :authorize, :except => [:index, :edit_issue, :update_issue,
                                        :agile_data, :update_agile_data]
  before_action :authorize_global, :only => [:index]

  accept_api_auth :agile_data, :update_agile_data

  helper :queries
  helper :issues
  helper :journals
  helper :projects
  helper :custom_fields
  include QueriesHelper

  def index
    retrieve_board_query
    return render_error(:status => :unprocessable_entity) unless @query.valid?

    @board_columns = @query.board_columns
    @swimlanes = @query.swimlanes
    respond_to do |format|
      format.html { render :layout => 'base' }
    end
  end

  # Drag & drop. The issue id is in the path, the destination in the body.
  #
  # The client reports only what it can know: the target column and the two
  # cards the dragged card landed between. Everything else — the rank itself,
  # whether the status change is legal — is decided here.
  def update
    unless @issue.editable?
      return render_move_error(l(:error_expert_agile_issue_not_editable), :forbidden)
    end

    target_status_id = params[:status_id].presence && params[:status_id].to_i
    if target_status_id && target_status_id != @issue.status_id
      unless status_allowed?(target_status_id)
        # Enforced explicitly. RedmineUP infers rejection by checking whether
        # the attribute still changed after safe_attributes= ran, comparing with
        # to_i — so any non-numeric attribute compares 0 == 0 and always passes.
        return render_move_error(l(:error_expert_agile_status_transition_not_allowed),
                                 :unprocessable_entity)
      end
    end

    retrieve_board_query
    siblings = column_siblings(target_status_id || @issue.status_id)

    Issue.transaction do
      @issue.init_journal(User.current)
      @issue.status_id = target_status_id if target_status_id
      assign_to_current_user_if_configured(target_status_id)

      unless @issue.save
        render_move_error(@issue.errors.full_messages.join(', '), :unprocessable_entity)
        raise ActiveRecord::Rollback
      end

      # Same transaction as the issue save: RedmineUP writes ranks in a separate
      # one, so a failed rank write leaves the card in its new column unranked.
      RedmineExpertAgile::BoardPositions.place!(
        @issue,
        :prev_issue => board_issue(params[:prev_id]),
        :next_issue => board_issue(params[:next_id]),
        :siblings => siblings
      )
    end
    return if performed?

    @issue.reload
    respond_to do |format|
      # Deliberately format.js, not format.json, even though the body is JSON.
      # Redmine's find_current_user ignores the session for api_request? — which
      # is any .json/.xml format — so a cookie-authenticated .json request is
      # anonymous and 403s. Only the REST endpoints below, which declare
      # accept_api_auth and authenticate by key, may use the API formats.
      format.js { render :json => move_payload }
      format.html { redirect_back_or_default project_expert_agile_board_path(@issue.project) }
    end
  end

  def issue_tooltip
    render :partial => 'expert_agile_boards/issue_tooltip', :locals => { :issue => @issue }
  end

  # --- REST API --------------------------------------------------------

  def agile_data
    respond_to do |format|
      format.api
    end
  end

  # Write agile data for one issue.
  #
  # RedmineUP exposes agile data read-only, so story points and sprint
  # assignment can only be set through nested attributes on the issue endpoint.
  # This makes it a first-class operation.
  def update_agile_data
    return head :forbidden unless @issue.editable?

    attributes = params[:expert_agile_data] || {}
    data = @issue.expert_agile_data || @issue.build_expert_agile_data

    if attributes.key?(:sprint_id) && attributes[:sprint_id].present?
      # Resolve against the sprints this issue's project may actually plan
      # into, so an id from elsewhere cannot be written in.
      sprint = @issue.project.shared_expert_agile_sprints.find_by(:id => attributes[:sprint_id])
      return render_api_errors(l(:error_expert_agile_container_not_available)) if sprint.nil?

      data.sprint_id = sprint.id
    elsif attributes.key?(:sprint_id)
      data.sprint_id = nil
    end

    data.story_points = attributes[:story_points].presence if attributes.key?(:story_points)

    if data.save
      respond_to { |format| format.api { render_api_ok } }
    else
      respond_to { |format| format.api { render_validation_errors(data) } }
    end
  end

  private

  def find_issue_for_board
    @issue = Issue.find(params[:id])
    @project = @issue.project
    raise ::Unauthorized unless @issue.visible?
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  SESSION_KEY = :expert_agile_query

  # The board being looked at.
  #
  # Mirrors Redmine's own retrieve_query: an explicit query_id wins, otherwise
  # `set_filter` builds a board from the request, otherwise the last board is
  # restored from the session. Without the session step, every option applied
  # from the panel — statuses, WIP limits, swimlanes — would be lost the moment
  # the page reloaded or the user came back via the menu, because those live in
  # the URL and nowhere else.
  #
  # Note this is display state only. What a *move* is allowed to do never comes
  # from here: the target status is checked against
  # `issue.new_statuses_allowed_to` and the issue's own permissions. That is the
  # part RedmineUP gets wrong — there the session query decides which columns
  # exist for the move itself.
  def retrieve_board_query
    if params[:query_id].present?
      @query = find_board_query(params[:query_id])
      @query.project = @project
      # A saved board can still be tweaked for this request without the change
      # being written back to it.
      if params[:set_filter].present?
        @query.build_from_params(params)
        @query.apply_board_params(params)
      end
      session[SESSION_KEY] = { :id => @query.id, :project_id => @query.project_id }
    elsif params[:set_filter].present? || session_state_stale?
      @query = ExpertAgileQuery.new(:name => '_', :project => @project)
      @query.build_from_params(params)
      @query.apply_board_params(params)
      store_board_session_state
    else
      @query = restore_board_from_session
    end
    @query
  end

  # Through `visible`, so a guessed id cannot open somebody else's private
  # board. Without it the id is the only thing standing between a project member
  # and another user's saved filter set.
  #
  # Both ways in go through here. The session carries only an id, and a session
  # outlives the query it points at: an owner turning a shared board private, or
  # a role losing the permission, has to take effect on the next request rather
  # than whenever the user next happens to pass a query_id.
  def visible_board_query(id)
    scope = ExpertAgileQuery.visible
    scope = scope.global_or_on_project(@project) if @project
    scope.find_by(:id => id)
  end

  def find_board_query(id)
    visible_board_query(id) || raise(ActiveRecord::RecordNotFound)
  end

  def session_state_stale?
    state = session[SESSION_KEY]
    state.nil? || state[:project_id] != (@project ? @project.id : nil)
  end

  # Only what is needed to rebuild the board, not the whole options blob.
  # RedmineUP stores the entire serialized options hash plus every filter in the
  # cookie session, which a large filter set can push past the 4 KB limit.
  def store_board_session_state
    session[SESSION_KEY] = {
      :project_id => @query.project_id,
      :filters => @query.filters,
      :group_by => @query.group_by,
      :column_names => @query.column_names,
      :sort => @query.sort_criteria.to_a,
      :board => @query.board_session_options
    }
  end

  def restore_board_from_session
    state = session[SESSION_KEY]
    if state[:id]
      saved = visible_board_query(state[:id])
      if saved
        saved.project = @project
        return saved
      end
      # Deleted since, or no longer visible to this user; fall through to a
      # fresh one rather than showing a board they may no longer open.
      session[SESSION_KEY] = nil
      return ExpertAgileQuery.new(:name => '_', :project => @project)
    end

    query = ExpertAgileQuery.new(:name => '_', :project => @project)
    query.filters = state[:filters] || {}
    query.group_by = state[:group_by]
    query.column_names = state[:column_names]
    query.sort_criteria = state[:sort] if state[:sort].present?
    query.restore_board_options(state[:board])
    query
  end

  def status_allowed?(status_id)
    @issue.new_statuses_allowed_to(User.current).map(&:id).include?(status_id)
  end

  # Optional convenience: claim an unassigned card by moving it. Only when the
  # status actually changes, and never overrides an existing assignee.
  def assign_to_current_user_if_configured(target_status_id)
    return unless RedmineExpertAgile.auto_assign_on_move?
    return unless target_status_id
    return if @issue.assigned_to_id.present?
    return unless @issue.assignable_users.include?(User.current)

    @issue.assigned_to_id = User.current.id
  end

  # Issues of the destination column in rank order, used only when a collapsed
  # gap forces a rebalance.
  def column_siblings(status_id)
    @query.board_scope
          .where(:status_id => status_id)
          .where.not(:id => @issue.id)
          .sorted_by_rank
  rescue StandardError
    Issue.where(:status_id => status_id, :project_id => @issue.project_id).sorted_by_rank
  end

  def board_issue(id)
    return nil if id.blank?

    Issue.where(:id => id).first
  end

  # The moved card plus fresh column aggregates, so the board can swap one card
  # and update the headers instead of reloading.
  def move_payload
    {
      :issueId => @issue.id,
      :statusId => @issue.status_id,
      :card => render_to_string(:partial => 'expert_agile_boards/issue_card',
                                :locals => { :issue => @issue },
                                :formats => [:html]),
      :columns => @query.board_columns.map(&:to_h)
    }
  end

  # A plain JSON contract. RedmineUP returns an HTML partial on success and a
  # JSON array on failure, both declared as format.html, and the client has to
  # sniff which it got.
  def render_move_error(message, status)
    @error_message = message
    respond_to do |format|
      format.js { render :json => { :error => message }, :status => status }
      format.html do
        flash[:error] = message
        redirect_back_or_default project_expert_agile_board_path(@issue.project)
      end
      format.api { render_api_errors(message) }
    end
  end
end
