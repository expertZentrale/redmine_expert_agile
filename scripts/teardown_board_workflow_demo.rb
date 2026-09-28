# Removes everything scripts/seed_board_workflow_demo.rb created.
#
#   DEMO_STACK=1 bundle exec rails runner \
#     plugins/redmine_expert_agile/scripts/teardown_board_workflow_demo.rb
#
# Only acts on what the seed recorded in its backup row, and deletes nothing
# at all without one. Deletes the three demo projects with their issues, journals, relations,
# versions, categories and saved boards; then, from the ids recorded in the
# "expert_agile_workflow_demo_backup" settings row, the demo workflow rules,
# trackers, statuses, roles, users and group; and restores the global settings
# the seed changed.

require 'json'

BACKUP_KEY = 'expert_agile_workflow_demo_backup'.freeze
PROJECT_IDENTS = %w[wf-board-sub wf-board-noagile wf-board].freeze

def say(msg)
  puts("[teardown] #{msg}")
end

unless ENV['DEMO_STACK'] == '1'
  abort 'refusing to run without DEMO_STACK=1. This script destroys projects, trackers, statuses, ' \
        'roles and users. Set it only on a disposable database.'
end

# The backup row is the only record of what the seed created. Without a valid
# one nothing is deleted at all — not even projects that merely carry a demo
# identifier.
backup = begin
  raw = Setting.where(:name => BACKUP_KEY).pick(:value)
  raw.blank? ? nil : JSON.parse(raw)
rescue JSON::ParserError => e
  abort "[teardown] backup row #{BACKUP_KEY} is not JSON (#{e.message}); nothing was deleted"
end
abort "[teardown] no backup row #{BACKUP_KEY} found; nothing was deleted" unless backup.is_a?(Hash)

# --- projects ------------------------------------------------------------------

projects = Project.where(:id => Array(backup['project_ids']), :identifier => PROJECT_IDENTS).to_a
issue_ids = Issue.where(:project_id => projects.map(&:id)).pluck(:id)
journal_ids = Journal.where(:journalized_type => 'Issue', :journalized_id => issue_ids).pluck(:id)

# delete_all, never destroy_all: other plugins hook Issue and Journal callbacks.
counts = {
  :expert_agile_data => ExpertAgileData.where(:issue_id => issue_ids).delete_all,
  :issue_relations => IssueRelation.where(:issue_from_id => issue_ids)
                                   .or(IssueRelation.where(:issue_to_id => issue_ids)).delete_all,
  :journal_details => JournalDetail.where(:journal_id => journal_ids).delete_all,
  :journals => Journal.where(:id => journal_ids).delete_all,
  :issues => Issue.where(:id => issue_ids).delete_all,
  :queries => Query.where(:project_id => projects.map(&:id)).where("type LIKE 'ExpertAgile%'").delete_all
}
counts.each { |table, count| say "  #{table}: #{count}" }

# Children first: a project with subprojects cannot be destroyed.
PROJECT_IDENTS.each do |ident|
  project = projects.detect { |candidate| candidate.identifier == ident }
  next if project.nil?

  project.reload.destroy
  say "project '#{ident}' destroyed"
end

# --- global rows -----------------------------------------------------------------

tracker_ids = (backup['tracker_ids'] || {}).values
status_ids = (backup['status_ids'] || {}).values
role_ids = (backup['role_ids'] || {}).values
rule_ids = Array(backup['workflow_rule_ids'])

# The global rows are removed all together or not at all. Each of them can
# have been put to use after the seed ran — and destroying it would take that
# use with it: a tracker's rules and project settings, a role's rules, a
# group's assignments, a user's memberships and authorship. The demo projects
# are gone by now, so every reference still found is somebody else's. If
# there is any, nothing global is touched and the backup row stays, so the
# teardown can be run again once those references are removed.
user_ids = Array(backup['user_ids'])
group_ids = Array(backup['group_id'])
principal_ids = user_ids + group_ids
outside = {
  'issues using a demo tracker or status' =>
    Issue.where(:tracker_id => tracker_ids).or(Issue.where(:status_id => status_ids)).pluck(:id),
  'workflow rules the seed did not write' =>
    WorkflowRule.where(:tracker_id => tracker_ids)
                .or(WorkflowRule.where(:old_status_id => status_ids))
                .or(WorkflowRule.where(:new_status_id => status_ids))
                .or(WorkflowRule.where(:role_id => role_ids))
                .where.not(:id => rule_ids).pluck(:id),
  'projects a demo tracker is enabled in' =>
    Project.joins(:trackers).where(:trackers => { :id => tracker_ids }).distinct.pluck(:identifier),
  'memberships of demo roles, users or the group' =>
    Member.joins(:member_roles).where(:member_roles => { :role_id => role_ids }).distinct.pluck(:id) |
      Member.where(:user_id => principal_ids).pluck(:id),
  'issues written by or assigned to a demo account or the group' =>
    Issue.where(:author_id => user_ids).or(Issue.where(:assigned_to_id => principal_ids)).pluck(:id),
  'journals written by a demo account' => Journal.where(:user_id => user_ids).pluck(:id),
  'group members the seed did not add' =>
    User.where(:id => Group.where(:id => group_ids).flat_map(&:user_ids) - user_ids).pluck(:login)
}.reject { |_, found| found.empty? }

if outside.any?
  outside.each { |what, found| say "WARNING: #{what}: #{found.first(20).inspect}#{found.size > 20 ? ' …' : ''}" }
  say 'global rows (trackers, statuses, roles, workflow rules, users, group, settings) left untouched; ' \
      'remove those references and run the teardown again'
  exit
end

say "workflow rules: #{WorkflowRule.where(:id => rule_ids).delete_all}"
Tracker.where(:id => tracker_ids).each(&:destroy)
IssueStatus.where(:id => status_ids).each(&:destroy)
say "trackers and statuses removed"
Role.where(:id => role_ids).each(&:destroy)
Group.where(:id => group_ids).each(&:destroy)
User.where(:id => user_ids).each(&:destroy)
say "roles, group and users removed"

(backup['settings'] || {}).each do |name, value|
  if value.nil?
    Setting.where(:name => name).delete_all
  else
    row = Setting.where(:name => name).first || Setting.new
    row.name = name
    row.value = value
    row.save(:validate => false)
  end
end
Setting.clear_cache if Setting.respond_to?(:clear_cache)
Setting.where(:name => BACKUP_KEY).delete_all
say 'global settings restored, backup row removed'
