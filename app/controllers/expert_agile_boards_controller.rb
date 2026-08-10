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

  def update_agile_data
    unless @issue.editable?
      return render_api_head(:forbidden)
    end

    data = @issue.expert_agile_data || @issue.build_expert_agile_data
    attributes = params[:expert_agile_data] || {}
    data.story_points = attributes[:story_points] if attributes.key?(:story_points)
    data.sprint_id = attributes[:sprint_id] if attributes.key?(:sprint_id)

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

  # The board a move is being made on, so WIP feedback and the column scope
  # come from the query the user is actually looking at.
  #
  # Taken from the request, never from the session. RedmineUP rebuilds it from
  # the session, so board columns and WIP limits are whatever that user last
  # rendered — which may be a different board entirely.
  def retrieve_board_query
    @query = if params[:query_id].present?
               scope = ExpertAgileQuery.where(:project_id => nil)
               scope = scope.or(ExpertAgileQuery.where(:project_id => @project)) if @project
               scope.find(params[:query_id])
             else
               ExpertAgileQuery.new(:name => '_', :project => @project)
             end
    @query.project = @project
    @query.build_from_params(params) if params[:query_id].blank?
    @query
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
