# The backlog planner: drag issues from the backlog into sprints or versions.
class ExpertAgileBacklogsController < ApplicationController
  menu_item :expert_agile_backlog

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :build_query
  before_action :find_issue_for_planning, :only => [:update]

  helper :queries
  helper :expert_agile_boards
  helper :issues
  include QueriesHelper

  def index
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

  def build_query
    @query = ExpertAgileBacklogQuery.new(:name => '_', :project => @project)
    @query.container_type = params[:container_type] if params[:container_type].present?
    @query.build_from_params(params)
    @query
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
