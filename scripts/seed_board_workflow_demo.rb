# Seeds a set of projects for testing the agile board by hand: restrictive,
# role-dependent workflows and issues covering every value a board can be
# grouped into swimlanes by.
#
#   DEMO_STACK=1 DEMO_PASSWORD=... bundle exec rails runner \
#     plugins/redmine_expert_agile/scripts/seed_board_workflow_demo.rb
#
# Meant for the screenshots stack (docker-compose.screenshots.yml, :3001), the
# disposable empty database. Removed again by
# scripts/teardown_board_workflow_demo.rb.
#
# What it builds:
#
# * Statuses Triage, Ready, Doing, Check: Review, Check: QA (one sub-column
#   pair), Accepted and Declined (both closed).
# * Trackers WF Feature (linear workflow), WF Defect (linear, and declinable
#   from anywhere), WF Chore (every transition open).
# * Roles WF Lead (every transition), WF Developer (the linear graphs; handing
#   a card to review only as its assignee; assignee read-only in review; due
#   date required for Accepted on features) and WF Reporter (may edit own
#   issues only; may decline, and reopen, their own issues only).
# * Users wf-lead, wf-dev, wf-dev2, wf-reporter and the admin wf-demo-admin,
#   all with DEMO_PASSWORD; the group "WF Team" (wf-dev, wf-dev2) as an
#   assignee, which covers the group branch of assignee-only transitions.
# * Projects wf-board, its subproject wf-board-sub (agile enabled) and
#   wf-board-noagile (agile module off: its cards must not be draggable on
#   the parent's board).
# * Issues spread over every tracker and status, with categories, versions,
#   priorities, done ratios, start and due dates, private flags, authors and
#   assignees varied; a parent with an open subtask (cannot be closed) and a
#   blocked issue (cannot be closed).
# * Saved boards: an ungrouped one, and one "Lanes: <field>" board per field
#   this Redmine offers for swimlanes, enumerated at runtime.
#
# At the end it prints the transition matrix Redmine itself computes for each
# user, tracker and status, as a table and as one JSON line (MATRIX_JSON).
#
# Global rows it creates (statuses, trackers, roles, workflow rules, users, the
# group) and the global settings it changes are recorded in the `settings` row
# "expert_agile_workflow_demo_backup"; the teardown script works from there.
#
# Modes:  DRY_RUN=1       report what a re-run would delete, and exit
#         DEMO_PASSWORD=  password of every demo account (random, printed, if unset)
#
# All data is synthetic. NOTE: writes into the database it is pointed at; it is
# meant for a disposable dev stack only.

require 'json'
require 'securerandom'

BACKUP_KEY = 'expert_agile_workflow_demo_backup'.freeze
PARENT_IDENT = 'wf-board'.freeze
SUB_IDENT = 'wf-board-sub'.freeze
NOAGILE_IDENT = 'wf-board-noagile'.freeze
PROJECT_IDENTS = [PARENT_IDENT, SUB_IDENT, NOAGILE_IDENT].freeze
ADMIN_LOGIN = 'wf-demo-admin'.freeze
SEED = 20_260_928
srand(SEED)

ActionMailer::Base.perform_deliveries = false

def say(msg)
  puts("[seed] #{msg}")
end

abort 'redmine_expert_agile is not installed' unless Redmine::Plugin.installed?(:redmine_expert_agile)

unless ENV['DEMO_STACK'] == '1'
  abort 'refusing to run without DEMO_STACK=1. This script creates statuses, trackers, roles, ' \
        'workflow rules and users, and overwrites global settings. Set it only on a disposable database.'
end

STATUSES = {
  'triage' => ['Triage', false], 'ready' => ['Ready', false], 'doing' => ['Doing', false],
  'review' => ['Check: Review', false], 'qa' => ['Check: QA', false],
  'accepted' => ['Accepted', true], 'declined' => ['Declined', true]
}.freeze
TRACKERS = { 'feature' => 'WF Feature', 'defect' => 'WF Defect', 'chore' => 'WF Chore' }.freeze

ISSUE_PERMISSIONS = %i[view_issues add_issues add_issue_notes view_private_notes
                       manage_subtasks manage_issue_relations view_expert_agile_board
                       edit_expert_agile_board view_expert_agile_charts
                       view_expert_agile_backlog add_expert_agile_queries].freeze
ROLES = {
  'lead' => ['WF Lead', ISSUE_PERMISSIONS + %i[edit_issues set_issues_private manage_expert_agile_sprints
                                               manage_expert_agile_backlog manage_public_expert_agile_queries]],
  'developer' => ['WF Developer', ISSUE_PERMISSIONS + %i[edit_issues]],
  'reporter' => ['WF Reporter', ISSUE_PERMISSIONS + %i[edit_own_issues set_own_issues_private]]
}.freeze

# login => [firstname, lastname, role key]
PEOPLE = {
  'wf-lead' => ['Lena', 'Hartmann', 'lead'],
  'wf-dev' => ['Dario', 'Novak', 'developer'],
  'wf-dev2' => ['Mira', 'Stein', 'developer'],
  'wf-reporter' => ['Rosa', 'Keller', 'reporter']
}.freeze
GROUP_NAME = 'WF Team'.freeze
GROUP_MEMBERS = %w[wf-dev wf-dev2].freeze

GLOBAL_SETTING_NAMES = %w[issue_group_assignment gravatar_enabled].freeze

# --- settings backup ------------------------------------------------------------

def raw_setting(name)
  Setting.where(:name => name).pick(:value)
end

def write_raw_setting!(name, value)
  row = Setting.where(:name => name).first || Setting.new
  row.name = name
  row.value = value
  row.save(:validate => false)
  Setting.clear_cache if Setting.respond_to?(:clear_cache)
end

def load_backup
  raw = raw_setting(BACKUP_KEY)
  raw.blank? ? nil : JSON.parse(raw)
end

def save_backup!(backup)
  write_raw_setting!(BACKUP_KEY, backup.to_json)
end

def demo_issue_ids
  project_ids = Project.where(:identifier => PROJECT_IDENTS).pluck(:id)
  Issue.where(:project_id => project_ids).pluck(:id)
end

# --- dry run --------------------------------------------------------------------

if ENV['DRY_RUN'].present?
  ids = demo_issue_ids
  say "DRY RUN — projects present: #{Project.where(:identifier => PROJECT_IDENTS).pluck(:identifier).inspect}"
  say "DRY RUN — would rebuild #{ids.size} issues, " \
      "#{Journal.where(:journalized_type => 'Issue', :journalized_id => ids).count} journals, " \
      "#{IssueRelation.where(:issue_from_id => ids).count} relations"
  say "DRY RUN — backup row present: #{load_backup ? 'yes' : 'no'}"
  exit
end

password = ENV['DEMO_PASSWORD'].presence || SecureRandom.alphanumeric(20)

# Read first: it is the only proof of what an earlier run created. Anything
# with a demo name that is not recorded here belongs to someone else.
backup = load_backup
backup ||= { 'settings' => GLOBAL_SETTING_NAMES.index_with { |name| raw_setting(name) } }

# This script overwrites passwords and the admin flag, and the teardown
# deletes the accounts, so a pre-existing account is reused only when an
# earlier run of this script created it. A matching login and mail prove
# nothing: both are predictable.
def demo_account!(login, mail, known_ids)
  existing = User.find_by(:login => login)
  return User.new(:login => login, :mail => mail) if existing.nil?
  return existing if known_ids.include?(existing.id)

  abort "refusing to reuse the account '#{login}' (##{existing.id}): it was not created by this " \
        'script. Rename or remove that account first.'
end

def demo_user!(login, firstname, lastname, password, backup, admin: false)
  user = demo_account!(login, "#{login}@example.com", Array(backup['user_ids']))
  user.firstname = firstname
  user.lastname = lastname
  user.language = 'en'
  user.admin = admin
  user.must_change_passwd = false
  user.status = User::STATUS_ACTIVE
  user.password = password
  user.password_confirmation = password
  user.save!
  # Recorded at once: a later account refused below must not leave this one
  # behind as an account no run can prove it created.
  backup['user_ids'] = Array(backup['user_ids']) | [user.id]
  save_backup!(backup)
  user
end

admin = demo_user!(ADMIN_LOGIN, 'Workflow', 'Admin', password, backup, :admin => true)
User.current = admin
people = PEOPLE.to_h do |login, (firstname, lastname, _role)|
  [login, demo_user!(login, firstname, lastname, password, backup)]
end

group = backup['group_id'] && Group.find_by(:id => backup['group_id'])
if group.nil?
  abort "group #{GROUP_NAME.inspect} already exists" if Group.where(:lastname => GROUP_NAME).exists?

  group = Group.new(:lastname => GROUP_NAME)
end
# Reusing the group resets its members; somebody added by hand since the last
# run would be dropped without a word, so that stops the seed instead.
strangers = group.users.reject { |user| Array(backup['user_ids']).include?(user.id) }
if strangers.any?
  abort "refusing to reset the group #{GROUP_NAME.inspect}: it has members this script did not add " \
        "(#{strangers.map(&:login).join(', ')}). Remove them first."
end
group.users = GROUP_MEMBERS.map { |login| people[login] }
group.save!
backup['group_id'] = group.id
save_backup!(backup)
say "users #{([admin] + people.values).map(&:login).join(', ')}, group ##{group.id} #{GROUP_NAME}"

# --- global rows: statuses, trackers, roles ----------------------------------------

status_ids = backup['status_ids'] || {}
STATUSES.each do |key, (name, closed)|
  status = status_ids[key] && IssueStatus.find_by(:id => status_ids[key])
  if status.nil?
    clash = IssueStatus.find_by(:name => name)
    abort "issue status #{name.inspect} already exists (##{clash.id})" if clash

    status = IssueStatus.create!(:name => name, :is_closed => closed)
  end
  status_ids[key] = status.id
  # Recorded as soon as it exists: a later abort must not strand it.
  backup['status_ids'] = status_ids
  save_backup!(backup)
end
# Board columns follow Redmine's status order: keep workflow order, at the end.
base_position = IssueStatus.where.not(:id => status_ids.values).maximum(:position).to_i
STATUSES.keys.each_with_index do |key, index|
  IssueStatus.where(:id => status_ids[key]).update_all(:position => base_position + index + 1)
end
statuses = status_ids.transform_values { |id| IssueStatus.find(id) }

tracker_ids = backup['tracker_ids'] || {}
TRACKERS.each do |key, name|
  tracker = tracker_ids[key] && Tracker.find_by(:id => tracker_ids[key])
  if tracker.nil?
    clash = Tracker.find_by(:name => name)
    abort "tracker #{name.inspect} already exists (##{clash.id})" if clash

    tracker = Tracker.create!(:name => name, :default_status_id => statuses['triage'].id)
  end
  tracker_ids[key] = tracker.id
  # Recorded as soon as it exists: a later abort must not strand it.
  backup['tracker_ids'] = tracker_ids
  save_backup!(backup)
end
trackers = tracker_ids.transform_values { |id| Tracker.find(id) }

role_ids = backup['role_ids'] || {}
ROLES.each do |key, (name, permissions)|
  role = role_ids[key] && Role.find_by(:id => role_ids[key])
  if role.nil?
    clash = Role.find_by(:name => name)
    abort "role #{name.inspect} already exists (##{clash.id})" if clash

    role = Role.new(:name => name)
  end
  role.permissions = permissions
  role.assignable = true
  role.issues_visibility = 'all'
  role.save!
  role_ids[key] = role.id
  # Recorded as soon as it exists: a later abort must not strand it.
  backup['role_ids'] = role_ids
  save_backup!(backup)
end
roles = role_ids.transform_values { |id| Role.find(id) }

backup['status_ids'] = status_ids
backup['tracker_ids'] = tracker_ids
backup['role_ids'] = role_ids
save_backup!(backup)

# --- workflows ---------------------------------------------------------------------
#
# Rebuilt from scratch on every run. Only rows for the demo roles exist on the
# demo trackers, so nothing else can widen them.

WorkflowRule.where(:id => Array(backup['workflow_rule_ids'])).delete_all

LINEAR = [%w[triage ready], %w[ready doing], %w[doing review], %w[review doing], %w[review qa],
          %w[qa doing], %w[qa accepted]].freeze

transitions = []
add = lambda do |role, tracker, from, to, author: false, assignee: false|
  transitions << { :type => 'WorkflowTransition', :role_id => roles[role].id,
                   :tracker_id => trackers[tracker].id, :old_status_id => statuses[from].id,
                   :new_status_id => statuses[to].id, :author => author, :assignee => assignee }
end

TRACKERS.each_key do |tracker|
  # Lead: every transition on every tracker.
  STATUSES.each_key do |from|
    STATUSES.each_key { |to| add.call('lead', tracker, from, to) unless from == to }
  end

  # Reporter: decline and reopen, own issues only.
  (STATUSES.keys - %w[accepted declined]).each do |from|
    add.call('reporter', tracker, from, 'declined', :author => true)
  end
  add.call('reporter', tracker, 'declined', 'triage', :author => true)
end

# Developer: the linear graph, where handing a card on to review is the
# assignee's move alone.
%w[feature defect].each do |tracker|
  LINEAR.each do |from, to|
    add.call('developer', tracker, from, to, :assignee => (from == 'doing' && to == 'review'))
  end
end
(STATUSES.keys - %w[accepted declined]).each { |from| add.call('developer', 'defect', from, 'declined') }
STATUSES.each_key do |from|
  STATUSES.each_key { |to| add.call('developer', 'chore', from, to) unless from == to }
end
existing_rule_ids = WorkflowRule.pluck(:id)
WorkflowTransition.insert_all(transitions)

permissions = []
%w[feature defect].each do |tracker|
  permissions << { :type => 'WorkflowPermission', :role_id => roles['developer'].id,
                   :tracker_id => trackers[tracker].id, :old_status_id => statuses['review'].id,
                   :field_name => 'assigned_to_id', :rule => 'readonly' }
end
permissions << { :type => 'WorkflowPermission', :role_id => roles['developer'].id,
                 :tracker_id => trackers['feature'].id, :old_status_id => statuses['accepted'].id,
                 :field_name => 'due_date', :rule => 'required' }
WorkflowPermission.insert_all(permissions)
# Exactly the rows this run inserted — not every row on a demo tracker or
# role, which could include one somebody added by hand between runs. The
# teardown deletes these and treats any other row as someone else's.
backup['workflow_rule_ids'] = WorkflowRule.where.not(:id => existing_rule_ids).pluck(:id)
save_backup!(backup)
say "#{transitions.size} workflow transitions, #{permissions.size} field rules"

# --- projects ------------------------------------------------------------------------

# Same rule as for accounts: a project with a demo identifier is only rebuilt
# when this script created it — the rebuild deletes its issues.
def demo_project!(ident, name, parent, modules, backup)
  project = Project.find_by(:identifier => ident)
  if project && !Array(backup['project_ids']).include?(project.id)
    abort "refusing to rebuild the project '#{ident}' (##{project.id}): it was not created by this script."
  end
  project ||= Project.new(:identifier => ident)
  project.name = name
  project.is_public = false
  project.inherit_members = false
  project.description = 'Synthetic data for testing the agile board by hand. See ' \
                        'plugins/redmine_expert_agile/scripts/seed_board_workflow_demo.rb.'
  project.save!
  project.set_parent!(parent) if parent && project.parent_id != parent.id
  project.enabled_module_names = modules
  project.save!
  backup['project_ids'] = (Array(backup['project_ids']) | [project.id])
  save_backup!(backup)
  project
end

agile_modules = %w[issue_tracking time_tracking expert_agile expert_agile_backlog]
parent = demo_project!(PARENT_IDENT, 'Workflow board', nil, agile_modules, backup)
sub = demo_project!(SUB_IDENT, 'Workflow board – sub', parent, agile_modules, backup)
noagile = demo_project!(NOAGILE_IDENT, 'Workflow board – no agile', parent, %w[issue_tracking], backup)
projects = [parent, sub, noagile]

# Guard first: everything below deletes.
projects.each do |project|
  abort "refusing to wipe unexpected project #{project.identifier}" unless PROJECT_IDENTS.include?(project.identifier)
end

issue_ids = Issue.where(:project_id => projects.map(&:id)).pluck(:id)
journal_ids = Journal.where(:journalized_type => 'Issue', :journalized_id => issue_ids).pluck(:id)
# delete_all, never destroy_all: other plugins hook Issue and Journal callbacks.
ExpertAgileData.where(:issue_id => issue_ids).delete_all
IssueRelation.where(:issue_from_id => issue_ids).or(IssueRelation.where(:issue_to_id => issue_ids)).delete_all
JournalDetail.where(:journal_id => journal_ids).delete_all
Journal.where(:id => journal_ids).delete_all
Issue.where(:id => issue_ids).delete_all
Query.where(:project_id => projects.map(&:id)).where("type LIKE 'ExpertAgile%'").delete_all
Version.where(:project_id => projects.map(&:id)).delete_all
IssueCategory.where(:project_id => projects.map(&:id)).delete_all
Member.where(:project_id => projects.map(&:id)).destroy_all
say "cleared #{issue_ids.size} previously seeded issues"

projects.each do |project|
  project.trackers = trackers.values
  project.save!
  people.each do |login, user|
    Member.create!(:project => project, :principal => user, :roles => [roles[PEOPLE[login][2]]])
  end
  Member.create!(:project => project, :principal => group, :roles => [roles['developer']])
end

categories = {
  parent.id => %w[Frontend Backend Operations].map { |name| IssueCategory.create!(:project => parent, :name => name) },
  sub.id => [IssueCategory.create!(:project => sub, :name => 'Documentation')],
  noagile.id => []
}

versions = {
  'closed' => Version.create!(:project => parent, :name => '1.0', :status => 'open'),
  'locked' => Version.create!(:project => parent, :name => '1.1', :status => 'open'),
  'open' => Version.create!(:project => parent, :name => '1.2', :status => 'open'),
  'shared' => Version.create!(:project => parent, :name => '2.0', :status => 'open', :sharing => 'tree')
}
say "projects #{projects.map(&:identifier).join(', ')}"

# --- global settings -------------------------------------------------------------------

# A group can only be an assignee when the installation allows it.
Setting.issue_group_assignment = '1'
Setting.gravatar_enabled = '0'

# --- issues ------------------------------------------------------------------------------

SUBJECTS = ['Export the report as CSV', 'Login form forgets the user name', 'Rotate the API keys',
            'Search ignores umlauts', 'Nightly backup runs twice', 'Dark mode for the dashboard',
            'Invoice PDF cuts off the footer', 'Upgrade the database driver', 'Onboarding checklist',
            'Rate limit the public endpoints', 'Broken link in the footer', 'Archive old tickets',
            'Translate the settings page', 'Slow query on the overview', 'Tidy up the cron jobs'].freeze
authors = people.values
assignees = people.values + [group, nil]
priorities = IssuePriority.active.to_a
done_ratios = [0, 10, 30, 50, 80, 100]

# "1.2" belongs to the parent only; "2.0" is shared down the tree, so it is the
# one version a subproject issue may be planned into.
version_choices = {
  parent.id => [nil, versions['open'], versions['shared']],
  sub.id => [nil, versions['shared']],
  noagile.id => [nil, versions['shared']]
}

counter = 0
build_issue = lambda do |project, tracker, status, **attrs|
  counter += 1
  issue = Issue.new(:project => project, :tracker => tracker, :status => status,
                    :subject => "#{SUBJECTS[counter % SUBJECTS.size]} (#{counter})",
                    :author => authors[counter % authors.size],
                    :assigned_to => assignees[counter % assignees.size],
                    :priority => priorities[counter % priorities.size],
                    :category => categories[project.id].empty? ? nil : [nil, *categories[project.id]][counter % (categories[project.id].size + 1)],
                    :fixed_version => version_choices[project.id][counter % version_choices[project.id].size],
                    :done_ratio => done_ratios[counter % done_ratios.size],
                    :start_date => counter.odd? ? Date.today - (counter % 20) : nil,
                    :due_date => (counter % 3).zero? ? Date.today + (counter % 30) : nil,
                    :is_private => (counter % 11).zero?)
  attrs.each { |name, value| issue.send("#{name}=", value) }
  issue.save!
  issue
end

issues = []
trackers.each_value do |tracker|
  statuses.each_value do |status|
    2.times { issues << build_issue.call(parent, tracker, status) }
  end
end
trackers.each_value do |tracker|
  %w[triage doing review].each { |key| issues << build_issue.call(sub, tracker, statuses[key]) }
end
%w[ready doing].each { |key| issues << build_issue.call(noagile, trackers['chore'], statuses[key]) }

# Cannot be closed: an open subtask.
epic = build_issue.call(parent, trackers['feature'], statuses['qa'],
                        :subject => 'Parent with an open subtask', :author => people['wf-dev'],
                        :assigned_to => people['wf-dev'])
build_issue.call(parent, trackers['chore'], statuses['doing'], :subject => 'Open subtask of the parent',
                                                              :parent_issue_id => epic.id)
# Cannot be closed: blocked by an open issue.
blocker = build_issue.call(parent, trackers['defect'], statuses['doing'], :subject => 'Blocking issue')
blocked = build_issue.call(parent, trackers['defect'], statuses['qa'], :subject => 'Blocked by an open issue',
                                                                       :author => people['wf-dev'],
                                                                       :assigned_to => people['wf-dev'])
IssueRelation.create!(:issue_from => blocker, :issue_to => blocked, :relation_type => IssueRelation::TYPE_BLOCKS)
# Group-assigned card in "Doing": the group's members may hand it to review.
build_issue.call(parent, trackers['feature'], statuses['doing'], :subject => 'Assigned to the team',
                                                                  :assigned_to => group)
# Feature without a due date for the "required for Accepted" rule.
build_issue.call(parent, trackers['feature'], statuses['qa'], :subject => 'Feature without a due date',
                                                              :due_date => nil, :assigned_to => people['wf-dev'])

# Versions closed/locked after the issues are on them: Redmine refuses to put
# an issue on a version that is no longer open.
closed_ones = Issue.where(:project_id => parent.id, :status_id => [statuses['accepted'].id, statuses['declined'].id])
closed_ones.limit(2).update_all(:fixed_version_id => versions['closed'].id)
Issue.where(:project_id => parent.id, :status_id => statuses['doing'].id).limit(2)
     .update_all(:fixed_version_id => versions['locked'].id)
versions['closed'].update!(:status => 'closed')
versions['locked'].update!(:status => 'locked')

total = Issue.where(:project_id => projects.map(&:id)).count
say "#{total} issues"

# --- saved boards --------------------------------------------------------------------

board_status_ids = STATUSES.keys.map { |key| statuses[key].id }
all_statuses = { 'status_id' => { :operator => '*', :values => [''] } }

new_board = lambda do |name, swimlane = nil|
  query = ExpertAgileQuery.new(:name => name, :project => parent, :user => admin,
                               :visibility => Query::VISIBILITY_PUBLIC)
  query.filters = all_statuses.deep_dup
  query.column_names = %i[tracker assigned_to category fixed_version done_ratio due_date]
  query.board_status_ids = board_status_ids
  query.color_base = 'tracker'
  query.show_avatar = '0'
  query.swimlane_field = swimlane if swimlane
  query.save!
  query
end

boards = [new_board.call('WF board')]
lanes = ExpertAgileQuery.new(:project => parent).groupable_columns
lanes.each do |column|
  boards << new_board.call("Lanes: #{column.caption}", column.name.to_s)
end
say "#{boards.size} saved boards (swimlane fields: #{lanes.map(&:name).join(', ')})"

save_backup!(backup)

# --- expected transitions ---------------------------------------------------------------
#
# Asked from Redmine itself, the way the board and its server check ask:
# per user, tracker and status, and for the four author/assignee cases.

matrix = {}
say ''
say 'Transitions each user may make (A = as author, S = as assignee, AS = both; plain = always):'
# The administrator is asked the way core asks for one: every role counts.
({ ADMIN_LOGIN => admin }).merge(people).each do |login, user|
  user_roles = (user.admin? ? Role.all.to_a : user.roles_for_project(parent)).select(&:consider_workflow?)
  matrix[login] = {}
  trackers.each do |tracker_key, tracker|
    matrix[login][tracker_key] = {}
    lines = STATUSES.keys.map do |from|
      cases = { '' => [false, false], 'A' => [true, false], 'S' => [false, true], 'AS' => [true, true] }
      found = cases.transform_values do |(author, assignee)|
        IssueStatus.new_statuses_allowed(statuses[from], user_roles, tracker, author, assignee)
                   .map { |status| status_ids.key(status.id) }.compact
      end
      matrix[login][tracker_key][from] = found
      always = found['']
      extra = %w[A S AS].filter_map do |label|
        more = found[label] - always
        more.any? ? "#{label}:#{more.join('/')}" : nil
      end
      "#{from}->[#{always.join(',')}]#{extra.any? ? " #{extra.join(' ')}" : ''}"
    end
    say "  #{login.ljust(14)} #{TRACKERS[tracker_key].ljust(11)} #{lines.join('  ')}"
  end
end
say ''
puts "MATRIX_JSON: #{JSON.generate(:statuses => status_ids, :trackers => tracker_ids, :matrix => matrix)}"

base = ENV['DEMO_BASE_URL'].presence || 'http://localhost:3001'
say ''
say "board        #{base}/projects/#{PARENT_IDENT}/expert_agile/board"
boards.each { |query| say "  #{query.name.ljust(28)} #{base}/projects/#{PARENT_IDENT}/expert_agile/board?query_id=#{query.id}" }
say "logins       #{([ADMIN_LOGIN] + people.keys).join(', ')}"
say ENV['DEMO_PASSWORD'].present? ? 'password     as given in DEMO_PASSWORD' : "password     #{password}"
