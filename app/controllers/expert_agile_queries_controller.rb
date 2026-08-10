# Saving, editing and deleting boards.
#
# A board is an ExpertAgileQuery, so this mirrors Redmine's own
# QueriesController rather than inventing a second way to persist one.
class ExpertAgileQueriesController < ApplicationController
  menu_item :expert_agile

  before_action :find_query, :only => [:edit, :update, :destroy]
  before_action :find_optional_project, :only => [:index, :new, :create]

  accept_api_auth :index

  helper :queries
  include QueriesHelper

  def index
    scope = saved_queries_scope
    scope = scope.global_or_on_project(@project) if @project
    @queries = scope.sorted.to_a

    respond_to do |format|
      format.html { redirect_to board_path }
      format.api { render :json => @queries.map { |q| { :id => q.id, :name => q.name } } }
    end
  end

  def new
    @query = query_class.new
    @query.project = @project
    @query.user = User.current
    @query.build_from_params(params)
    @query.apply_board_params(params)
  end

  def create
    @query = query_class.new
    @query.project = @project
    @query.user = User.current
    @query.attributes = query_attributes
    @query.build_from_params(params)
    @query.apply_board_params(params)

    if save_allowed? && @query.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to board_path(:query_id => @query.id)
    else
      @query.errors.add(:base, l(:error_expert_agile_board_not_saveable)) unless save_allowed?
      render :action => 'new', :layout => 'base'
    end
  end

  def edit; end

  def update
    @query.attributes = query_attributes
    @query.build_from_params(params)
    @query.apply_board_params(params)

    if @query.save
      flash[:notice] = l(:notice_successful_update)
      redirect_to board_path(:query_id => @query.id)
    else
      render :action => 'edit', :layout => 'base'
    end
  end

  def destroy
    @query.destroy
    redirect_to board_path
  end

  private

  # Overridden by the charts variant, which is the same controller against a
  # different query class.
  def query_class
    ExpertAgileQuery
  end

  def saved_queries_scope
    query_class.where(:type => query_class.name).visible
  end

  def find_query
    @query = query_class.find(params[:id])
    @project = @query.project
    render_403 unless @query.editable_by?(User.current)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # Query does not include Redmine::SafeAttributes, so the assignable
  # attributes are listed explicitly rather than handed the raw params.
  def query_attributes
    attrs = params[:query] || {}
    permitted = {}
    permitted[:name] = attrs[:name] if attrs.key?(:name)
    permitted[:description] = attrs[:description] if attrs.key?(:description)
    if attrs.key?(:visibility) &&
       User.current.allowed_to?(:manage_public_expert_agile_queries, @project, :global => true)
      permitted[:visibility] = attrs[:visibility]
    end
    permitted
  end

  # A private board only needs the "save boards" permission; a public one needs
  # the manage permission, matching how the query itself decides editability.
  def save_allowed?
    if @query.is_private?
      User.current.allowed_to?(:add_expert_agile_queries, @project, :global => @project.nil?)
    else
      User.current.allowed_to?(:manage_public_expert_agile_queries, @project, :global => @project.nil?)
    end
  end

  # Where to land after saving — the board, or the charts page for the charts
  # variant.
  def board_path(options = {})
    if @project
      project_expert_agile_board_path(@project, options)
    else
      expert_agile_board_path(options)
    end
  end
end
