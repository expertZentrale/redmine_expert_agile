# The backlog planner: drag issues from the backlog into sprints or versions.
class ExpertAgileBacklogsController < ApplicationController
  menu_item :expert_agile_backlog

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :retrieve_backlog_query
  before_action :find_issue_for_planning, :only => [:update]

  helper :queries
  helper :expert_agile_boards
  helper :issues
  include QueriesHelper

  def index
    return render_error(:status => :unprocessable_entity) unless @query.valid?

    respond_to do |format|
      format.html { render :layout => 'base' }
    end
  end

  def update
    unless @issue.editable?
      return render_planning_error(l(:error_expert_agile_issue_not_editable), :forbidden)
    end

    target = @query.container_for(params[:container_id])
    if params[:container_id].present? && target.nil?
      # An id that is not among the containers this project may plan into. A
      # crafted id must not be able to move an issue into another project's
      # sprint.
      return render_planning_error(l(:error_expert_agile_container_not_available),
                                   :unprocessable_entity)
    end

    Issue.transaction do
      @issue.init_journal(User.current)
      assign_container(target)

      unless @issue.save
        render_planning_error(@issue.errors.full_messages.join(', '), :unprocessable_entity)
        raise ActiveRecord::Rollback
      end

      RedmineExpertAgile::BoardPositions.place!(
        @issue,
        :prev_issue => planning_issue(params[:prev_id]),
        :next_issue => planning_issue(params[:next_id]),
        :siblings => @query.siblings_for(target)
      )
    end
    return if performed?

    @issue.reload
    respond_to do |format|
      format.js { render :json => planning_payload(target) }
      format.html { redirect_to project_expert_agile_backlog_path(@project) }
    end
  end

  def load_more
    @container = @query.container_for(params[:container_id])
    @issues = @container ? @query.issues_for(@container) : @query.backlog_issues
    render :partial => 'expert_agile_backlogs/issue_list', :locals => { :issues => @issues }
  end

  def autocomplete
    @issues = @query.backlog_issues(params[:term])
    render :partial => 'expert_agile_backlogs/issue_list', :locals => { :issues => @issues }
  end

  private

  SESSION_KEY = :expert_agile_backlog_query

  # The backlog being looked at.
  #
  # The same three-way retrieval the board uses: an explicit query_id wins,
  # otherwise `set_filter` builds a backlog from the request, otherwise the last
  # one is restored from the session. Without the session step every filter and
  # option applied from the panel would be lost the moment the page reloaded or
  # the user came back via the project menu, because those live in the URL and
  # nowhere else.
  #
  # It runs for every action, not just #index: a planning move ranks the dragged
  # card within `siblings_for`, which is filtered, so the move has to see the
  # same backlog the user is looking at. Its own key, because the board's
  # session state is a different query class.
  def retrieve_backlog_query
    if params[:query_id].present?
      @query = find_backlog_query(params[:query_id])
      @query.project = @project
      # A saved backlog can still be tweaked for this request without the change
      # being written back to it.
      if params[:set_filter].present?
        @query.build_from_params(params)
        @query.apply_board_params(params)
      end
      # The sprint/version switch is a plain link, so it arrives without
      # set_filter. Honouring it here is what keeps the switch working on a saved
      # backlog; like every other tweak on this path it is not written back, so
      # the next bare request shows the backlog as it was saved.
      @query.container_type = params[:container_type] if params[:container_type].present?
      session[SESSION_KEY] = { :id => @query.id, :project_id => @query.project_id }
    elsif params[:set_filter].present? || session_state_stale?
      @query = ExpertAgileBacklogQuery.new(:name => '_', :project => @project)
      @query.build_from_params(params)
      @query.apply_board_params(params)
      store_backlog_session_state
    else
      @query = restore_backlog_from_session
    end
    @query
  end

  def find_backlog_query(id)
    scope = ExpertAgileBacklogQuery.where(:project_id => nil)
    scope = scope.or(ExpertAgileBacklogQuery.where(:project_id => @project)) if @project
    scope.find(id)
  end

  def session_state_stale?
    state = session[SESSION_KEY]
    state.nil? || state[:project_id] != (@project ? @project.id : nil)
  end

  # Only what is needed to rebuild the backlog, not the whole options blob — a
  # large filter set would otherwise push the cookie session past its 4 KB limit.
  def store_backlog_session_state
    session[SESSION_KEY] = {
      :project_id => @query.project_id,
      :filters => @query.filters,
      :group_by => @query.group_by,
      :column_names => @query.column_names,
      :sort => @query.sort_criteria.to_a,
      :board => @query.board_session_options
    }
  end

  def restore_backlog_from_session
    state = session[SESSION_KEY]
    if state[:id]
      saved = ExpertAgileBacklogQuery.find_by(:id => state[:id])
      if saved
        saved.project = @project
        return saved
      end
      # The saved backlog was deleted since; fall through to a fresh one.
      session[SESSION_KEY] = nil
      return ExpertAgileBacklogQuery.new(:name => '_', :project => @project)
    end

    query = ExpertAgileBacklogQuery.new(:name => '_', :project => @project)
    query.filters = state[:filters] || {}
    query.group_by = state[:group_by]
    query.column_names = state[:column_names]
    query.sort_criteria = state[:sort] if state[:sort].present?
    query.restore_board_options(state[:board])
    query
  end

  def find_issue_for_planning
    @issue = Issue.find(params[:id])
    raise ::Unauthorized unless @issue.visible?
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def assign_container(target)
    if @query.sprints?
      @issue.expert_agile_data!.sprint_id = target && target.id
    else
      @issue.fixed_version_id = target && target.id
    end
  end

  def planning_issue(id)
    return nil if id.blank?

    Issue.where(:id => id).first
  end

  def planning_payload(target)
    {
      :issueId => @issue.id,
      :containerId => target && target.id,
      :card => render_to_string(:partial => 'expert_agile_backlogs/issue_card',
                                :locals => { :issue => @issue },
                                :formats => [:html]),
      :totals => {
        :container => target ? @query.totals_for(target) : nil,
        :backlog => @query.totals_for(nil)
      }
    }
  end

  def render_planning_error(message, status)
    respond_to do |format|
      format.js { render :json => { :error => message }, :status => status }
      format.html do
        flash[:error] = message
        redirect_to project_expert_agile_backlog_path(@project)
      end
    end
  end
end
