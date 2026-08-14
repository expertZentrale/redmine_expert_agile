# Removes everything scripts/seed_screenshot_demo.rb created.
#
#   DEMO_STACK=1 bundle exec rails runner \
#     plugins/redmine_expert_agile/scripts/teardown_screenshot_demo.rb
#
# Deletes the demo project with its issues, journals, sprints, saved boards and
# time entries, the demo trackers/statuses/workflow transitions, and the capture
# user with its synthetic team. It then restores every global setting the seed
# overwrote, byte for byte, from the `expert_agile_screenshot_backup` row the
# seed wrote — including the absence of keys that were never stored, which is
# why the restore writes the raw column instead of going through
# Setting.plugin_redmine_expert_agile=.
#
#   KEEP_USER=1      leave the capture user and the demo team in place
#   KEEP_SETTINGS=1  leave the global settings as the seed left them

require 'json'

IDENT = 'screenshot-agile'.freeze
LOGIN = 'screenshot-agile-demo'.freeze
TEAM = %w[ada-demo linus-demo grace-demo kent-demo].freeze
BACKUP_KEY = 'expert_agile_screenshot_backup'.freeze

def say(msg)
  puts("[teardown] #{msg}")
end

# Same explicit opt-in as the seed script, and for the same reason: the stack
# this is written for boots in production mode, so Rails.env cannot tell a
# disposable database from a real one.
unless ENV['DEMO_STACK'] == '1'
  abort 'refusing to run without DEMO_STACK=1. This script destroys a project with its issues ' \
        'and journals, deletes trackers, statuses and users, and overwrites global settings. ' \
        'Set it only against a disposable database.'
end

backup = begin
  raw = Setting.where(:name => BACKUP_KEY).pick(:value)
  raw.blank? ? nil : JSON.parse(raw)
end

# --- project -------------------------------------------------------------------

project = Project.find_by(:identifier => IDENT)
if project.nil?
  say "no project with identifier '#{IDENT}', nothing to delete"
else
  # Guard: never let this loose on anything but the demo project.
  abort "refusing: project ##{project.id} has identifier '#{project.identifier}'" unless
    project.identifier == IDENT

  issue_ids = Issue.where(:project_id => project.id).pluck(:id)
  sprint_ids = ExpertAgileSprint.where(:project_id => project.id).pluck(:id)
  journal_ids = Journal.where(:journalized_type => 'Issue', :journalized_id => issue_ids).pluck(:id)
  say "project ##{project.id}, #{issue_ids.size} issues, #{journal_ids.size} journals"

  counts = {
    # Two queries, one count: the second catches rows whose issue lives in
    # another project but which point at a sprint this project shared down the
    # tree. The first query's rows are already gone, so nothing is counted twice.
    :expert_agile_data => ExpertAgileData.where(:issue_id => issue_ids).delete_all +
                          ExpertAgileData.where(:sprint_id => sprint_ids).delete_all,
    :expert_agile_sprints => ExpertAgileSprint.where(:id => sprint_ids).delete_all,
    :expert_agile_colors => ExpertAgileColor.where(:container_type => 'Issue',
                                                   :container_id => issue_ids).delete_all,
    :queries => Query.where(:project_id => project.id).where("type LIKE 'ExpertAgile%'").delete_all,
    :time_entries => TimeEntry.where(:project_id => project.id).delete_all,
    :journal_details => JournalDetail.where(:journal_id => journal_ids).delete_all,
    :journals => Journal.where(:id => journal_ids).delete_all,
    :issues => Issue.where(:id => issue_ids).delete_all,
    :versions => Version.where(:project_id => project.id).delete_all
  }
  counts.each { |table, count| say "  #{table}: #{count}" }

  project.destroy
  say "project '#{IDENT}' destroyed"
end

# --- global rows ----------------------------------------------------------------

if backup.nil?
  say 'WARNING: no backup row found — global settings, demo trackers and demo statuses were ' \
      'left untouched. Restore them by hand.'
else
  workflow_ids = Array(backup['workflow_ids'])
  say "workflow transitions: #{WorkflowTransition.where(:id => workflow_ids).delete_all}"

  tracker_ids = (backup['tracker_ids'] || {}).values
  status_ids = (backup['status_ids'] || {}).values
  ExpertAgileColor.where(:container_type => 'Tracker', :container_id => tracker_ids).delete_all
  ExpertAgileColor.where(:container_type => 'IssueStatus', :container_id => status_ids).delete_all

  # Anything outside the demo project that adopted a demo tracker or status in
  # the meantime keeps it — dropping the row would orphan real issues.
  used_trackers = Issue.where(:tracker_id => tracker_ids).distinct.pluck(:tracker_id)
  used_statuses = Issue.where(:status_id => status_ids).distinct.pluck(:status_id)
  abort "refusing to delete trackers still in use: #{used_trackers.inspect}" if used_trackers.any?
  abort "refusing to delete statuses still in use: #{used_statuses.inspect}" if used_statuses.any?

  WorkflowRule.where(:tracker_id => tracker_ids).delete_all
  WorkflowRule.where(:old_status_id => status_ids).delete_all
  WorkflowRule.where(:new_status_id => status_ids).delete_all
  say "trackers: #{Tracker.where(:id => tracker_ids).delete_all}, " \
      "statuses: #{IssueStatus.where(:id => status_ids).delete_all}"

  if ENV['KEEP_SETTINGS'] == '1'
    say 'settings left as the seed wrote them (KEEP_SETTINGS=1)'
  else
    (backup['settings'] || {}).each do |name, value|
      if value.nil?
        # The row did not exist before the seed ran.
        Setting.where(:name => name).delete_all
        next
      end

      unless Setting.where(:name => name).exists?
        row = Setting.new
        row.name = name
        row.save(:validate => false)
      end
      Setting.where(:name => name).update_all(:value => value, :updated_on => Time.current)
    end
    Setting.where(:name => BACKUP_KEY).delete_all
    Setting.clear_cache
    say "settings restored: #{(backup['settings'] || {}).keys.join(', ')}"
  end
end

# --- users -----------------------------------------------------------------------

if ENV['KEEP_USER'] == '1'
  say 'capture user and demo team kept (KEEP_USER=1)'
else
  ([LOGIN] + TEAM).each do |login|
    user = User.find_by(:login => login)
    next if user.nil?

    Member.where(:user_id => user.id).delete_all
    user.destroy
    say "user '#{login}' destroyed"
  end
end

say "remaining projects: #{Project.count}"
