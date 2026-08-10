# Admin screen for assigning card colours to trackers, priorities and statuses.
class ExpertAgileColorsController < ApplicationController
  layout 'admin'
  self.main_menu = false

  before_action :require_admin
  before_action :find_container_class

  def index
    @containers = @container_class.all.to_a
    @colors = ExpertAgileColor.where(:container_type => ExpertAgileColor.storage_type(@container_class))
                              .pluck(:container_id, :color).to_h
  end

  def update
    submitted = params[:colors] || {}
    ExpertAgileColor.transaction do
      submitted.each do |container_id, color|
        apply_color(container_id, color)
      end
    end
    flash[:notice] = l(:notice_successful_update)
    redirect_to expert_agile_colors_path(:container_type => params[:container_type])
  end

  private

  # The container class comes from the URL, so it is resolved through an
  # explicit whitelist. RedmineUP does `Object.const_get(params[:object_type].camelcase)`
  # here and relies on a later `respond_to?('color')` check to catch the damage.
  def find_container_class
    @container_class = ExpertAgileColor.container_class(params[:container_type])
    render_404 if @container_class.nil?
  end

  def apply_color(container_id, color)
    container = @container_class.find_by(:id => container_id)
    return if container.nil?

    record = ExpertAgileColor.find_or_initialize_by(:container_type => ExpertAgileColor.storage_type(@container_class),
                                                    :container_id => container.id)
    if color.blank?
      record.destroy if record.persisted?
    else
      record.color = color
      record.save
    end
  end
end
