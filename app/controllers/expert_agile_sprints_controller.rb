# Sprint CRUD, scoped to a project.
class ExpertAgileSprintsController < ApplicationController
  menu_item :expert_agile

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_sprint, :only => [:show, :edit, :update, :destroy]

  accept_api_auth :index, :show, :create, :update, :destroy

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
    @sprint.destroy
    respond_to do |format|
      format.html do
        flash[:notice] = l(:notice_successful_delete)
        redirect_to project_expert_agile_sprints_path(@project)
      end
      format.api { render_api_ok }
    end
  end

  private

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
