# Sprint CRUD, scoped to a project.
class ExpertAgileSprintsController < ApplicationController
  menu_item :expert_agile

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_sprint, :only => [:show, :edit, :update, :destroy, :complete]

  accept_api_auth :index, :show, :create, :update, :destroy, :complete

  def index
    @sprints = @project.expert_agile_sprints.sorted.to_a
    respond_to do |format|
      format.html
      format.api
    end
  end

  def show
    respond_to do |format|
      format.html { redirect_to project_expert_agile_sprints_path(@project) }
      format.api
    end
  end

  def new
    @sprint = @project.expert_agile_sprints.build(default_sprint_attributes)
  end

  def create
    @sprint = @project.expert_agile_sprints.build
    @sprint.safe_attributes = sprint_params

    if @sprint.save
      respond_to do |format|
        format.html do
          flash[:notice] = l(:notice_successful_create)
          redirect_to project_expert_agile_sprints_path(@project)
        end
        format.api { render :action => 'show', :status => :created }
      end
    else
      respond_to do |format|
        format.html { render :action => 'new' }
        format.api { render_validation_errors(@sprint) }
      end
    end
  end

  def edit; end

  def update
    @sprint.safe_attributes = sprint_params

    if @sprint.save
      respond_to do |format|
        format.html do
          flash[:notice] = l(:notice_successful_update)
          redirect_to project_expert_agile_sprints_path(@project)
        end
        format.api { render_api_ok }
      end
    else
      respond_to do |format|
        format.html { render :action => 'edit' }
        format.api { render_validation_errors(@sprint) }
      end
    end
  end

  def destroy
    unless @sprint.destroy
      respond_to do |format|
        format.html do
          flash[:error] = @sprint.errors.full_messages.join(', ')
          redirect_to project_expert_agile_sprints_path(@project)
        end
        format.api { render_validation_errors(@sprint) }
      end
      return
    end

    respond_to do |format|
      format.html do
        flash[:notice] = l(:notice_successful_delete)
        redirect_to project_expert_agile_sprints_path(@project)
      end
      format.api { render_api_ok }
    end
  end

  # Completes a sprint in one step: the form on GET, the completion on POST.
  # See RedmineExpertAgile::SprintCompletion for what happens to the issues.
  def complete
    @completion = RedmineExpertAgile::SprintCompletion.new(@sprint)
    if @sprint.closed?
      return complete_refused(l(:error_expert_agile_sprint_already_closed))
    end
    return render_complete_form if request.get?

    target = params[:target].presence || RedmineExpertAgile::SprintCompletion::TARGET_NEXT
    activate = params.key?(:activate_target) ? params[:activate_target].to_s.in?(%w(1 true)) : target.to_s != 'backlog'
    if @completion.complete(target, :activate => activate,
                                    :new_sprint_attributes => (params[:new_sprint] || {}).to_unsafe_h)
      respond_to do |format|
        format.html do
          flash[:notice] = completed_notice
          redirect_back_or_default project_expert_agile_sprints_path(@project)
        end
        format.api { render_api_completion }
      end
    else
      respond_to do |format|
        format.html { render_complete_form(:unprocessable_entity) }
        format.api do
          render :json => { :errors => completion_errors,
                            :refused_issues => @completion.refusals.map { |r| refused_issue_json(r) } },
                 :status => :unprocessable_entity
        end
      end
    end
  end

  private

  def render_complete_form(status = :ok)
    @open_issues = @completion.open_issues
    @new_sprint = @completion.new_sprint ||
                  @project.expert_agile_sprints.build(@completion.suggested_new_sprint_attributes)
    respond_to do |format|
      format.html { render :action => 'complete', :status => status }
      format.api { render_api_completion_preview }
    end
  end

  def complete_refused(message)
    respond_to do |format|
      format.html do
        flash[:error] = message
        redirect_back_or_default project_expert_agile_sprints_path(@project)
      end
      format.api { render :json => { :errors => [message] }, :status => :unprocessable_entity }
    end
  end

  def completed_notice
    destination = @completion.destination
    l(:notice_expert_agile_sprint_completed,
      :sprint => @sprint.name, :count => @completion.moved.size,
      :target => destination ? destination.name : l(:label_expert_agile_backlog))
  end

  def completion_errors
    (@sprint.errors.full_messages + (@completion.new_sprint ? @completion.new_sprint.errors.full_messages : [])).uniq
  end

  # A refusal names the issue only where the caller may see it.
  def refused_issue_json(refusal)
    visible = refusal.issue.visible?
    { :id => visible ? refusal.issue.id : nil, :reason => refusal.reason }
  end

  def render_api_completion
    destination = @completion.destination
    render :json => { :sprint_id => @sprint.id, :status => @sprint.status_name,
                      :moved_issue_ids => @completion.moved.map(&:id),
                      :target_sprint_id => destination && destination.id,
                      :target_status => destination && destination.reload.status_name }
  end

  # GET on the API: what a completion would move, and where "next" points.
  def render_api_completion_preview
    next_sprint = @completion.next_sprint
    render :json => { :sprint_id => @sprint.id,
                      :open_issue_count => @open_issues.size, :closed_issue_count => @completion.closed_issue_count,
                      :next_sprint_id => next_sprint && next_sprint.id }
  end

  def find_sprint
    @sprint = @project.expert_agile_sprints.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def sprint_params
    (params[:expert_agile_sprint] || {}).to_unsafe_h
  end

  # A sensible two-week sprint starting today, so the form opens filled in.
  def default_sprint_attributes
    today = User.current.today
    { :start_date => today, :end_date => today + 13 }
  end
end
