# Agile charts: the page, and the JSON the chart canvas is drawn from.
class ExpertAgileChartsController < ApplicationController
  menu_item :expert_agile_charts

  before_action :find_optional_project
  before_action :authorize_chart_access
  before_action :build_query

  helper :queries
  helper :expert_agile_boards
  include QueriesHelper

  def show
    respond_to do |format|
      format.html { render :layout => 'base' }
    end
  end

  # Chart series, computed server-side and cached.
  #
  # format.js rather than format.json: Redmine's find_current_user ignores the
  # session for api_request?, so a .json request from the browser would
  # authenticate as anonymous.
  def render_chart
    if @query.too_many_items?
      return render :json => { :error => l(:text_expert_agile_chart_too_many_items) },
                    :status => :unprocessable_entity
    end

    payload = cached_chart_data
    return render :json => { :error => l(:label_none) }, :status => :not_found if payload.nil?

    render :json => payload
  end

  private

  def authorize_chart_access
    if @project
      authorize
    else
      authorize_global
    end
  end

  def build_query
    @query = if params[:query_id].present?
               scope = ExpertAgileChartsQuery.where(:project_id => nil)
               scope = scope.or(ExpertAgileChartsQuery.where(:project_id => @project)) if @project
               scope.find(params[:query_id])
             else
               ExpertAgileChartsQuery.new(:name => '_', :project => @project)
             end
    @query.project = @project
    apply_chart_params
    @query
  end

  def apply_chart_params
    @query.build_from_params(params) if params[:query_id].blank?
    @query.chart = params[:chart] if params[:chart].present?
    @query.chart_unit = params[:chart_unit] if params[:chart_unit].present?
    @query.interval = params[:interval] if params[:interval].present?
    @query.date_from = params[:date_from] if params[:date_from].present?
    @query.date_to = params[:date_to] if params[:date_to].present?
  end

  # Historical series are immutable for past dates, so caching them is free
  # correctness-wise as long as the key covers everything that could change the
  # result. RedmineUP caches nothing.
  def cached_chart_data
    return compute_chart_data unless RedmineExpertAgile.chart_cache?

    Rails.cache.fetch(@query.cache_key,
                      :expires_in => RedmineExpertAgile.chart_cache_minutes.minutes) do
      compute_chart_data
    end
  end

  def compute_chart_data
    chart = @query.build_chart
    return nil if chart.nil?

    chart.data.merge(:chart => @query.chart, :chart_unit => @query.chart_unit)
  end
end
