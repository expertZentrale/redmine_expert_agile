# The epics of a project as a tree: each epic with its stories and their
# subtasks, how far each one is along, and who is on it.
#
# Read-only on purpose. Moving work between epics is the board's and the
# planner's job, under their rules; this page is the overview Jira's epic
# list gives, built from the same subtask tree.
class ExpertAgileEpicsController < ApplicationController
  menu_item :expert_agile_epics

  helper :expert_agile_boards

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :require_epics

  def index
    @show_closed = params[:closed] == '1'
    scope = Issue.visible
                 .where(:tracker_id => RedmineExpertAgile::Epics.tracker_ids)
                 .where(:project_id => @project.self_and_descendants.select(:id))
    @closed_count = @show_closed ? 0 : scope.joins(:status).where(IssueStatus.table_name => { :is_closed => true }).count
    scope = scope.open unless @show_closed
    @epics = scope.includes(:status, :tracker, :assigned_to).order(:subject).to_a
    @progress = RedmineExpertAgile::Epics.progress(@epics)
    @rows = RedmineExpertAgile::Hierarchy.descendant_rows(@epics)
  end

  private

  def require_epics
    render_404 unless RedmineExpertAgile::Epics.enabled?
  end
end
