# Seeds a self-contained demo project used to generate the README screenshots.
#
#   bundle exec rails runner plugins/redmine_expert_agile/scripts/seed_screenshot_demo.rb
#
# Everything it creates lives inside a single project (identifier
# "screenshot-agile") and is removed again by scripts/teardown_screenshot_demo.rb.
#
# UNLIKE the helpdesk equivalent this script DOES write global state, because
# the plugin cannot be shown without it: story points and sprints are off by
# default, board columns are issue status names (an installation's own statuses
# make for unreadable screenshots), and the capture browser must not be sent to
# Gravatar. Every global value it overwrites, plus the ids of every global row
# it creates, is stored verbatim in a `settings` row named
# "expert_agile_screenshot_backup" and printed below; the teardown script
# restores the instance from there.
#
# Modes:
#   DRY_RUN=1       report what the wipe step would delete, then exit
#   RELABEL=de|en   only rename the demo statuses, then exit — run this between
#                   the English and the German capture pass so both screenshot
#                   sets share one dataset (and one set of issue ids)
#   DEMO_PASSWORD=  password for the capture user (random and printed if unset)
#
# All data is synthetic. NOTE: this writes into whatever database it is pointed
# at; it is meant for a disposable dev stack.

require 'json'
require 'securerandom'

IDENT = 'screenshot-agile'.freeze
LOGIN = 'screenshot-agile-demo'.freeze
BACKUP_KEY = 'expert_agile_screenshot_backup'.freeze
SEED = 20_260_814
TODAY = Time.current
TODAY_D = TODAY.to_date

srand(SEED)
ActionMailer::Base.perform_deliveries = false

def say(msg)
  puts("[seed] #{msg}")
end

abort 'redmine_expert_agile is not installed' unless Redmine::Plugin.installed?(:redmine_expert_agile)

# Statuses are the board's column headers and trackers are its card colours, so
# both carry the label a reader sees. Tracker names are the same in both
# languages on purpose — "Story"/"Bug"/"Task" are the words German agile teams
# use too, and "Fehler"/"Aufgabe" would collide with trackers that already exist
# on a German installation.
TRACKER_LABELS = { 'story' => 'Story', 'bug' => 'Bug', 'task' => 'Task' }.freeze
STATUS_LABELS = {
  'en' => { 'backlog' => 'Backlog', 'todo' => 'To do', 'progress' => 'In Progress',
            'review' => 'Dev: Review', 'test' => 'Dev: Test', 'done' => 'Done',
            'archived' => 'Archived' },
  'de' => { 'backlog' => 'Backlog', 'todo' => 'Zu erledigen', 'progress' => 'In Arbeit',
            'review' => 'Dev: Review', 'test' => 'Dev: Test', 'done' => 'Fertig',
            'archived' => 'Archiviert' }
}.freeze
# Only these become board columns. The other two are deliberately off the board:
# "backlog" is the product backlog the planner drags from, and "archived" is the
# release history the charts replay — on the board they would bury the sprint in
# a hundred cards nobody is working on.
BOARD_STATUS_KEYS = %w[todo progress review test done].freeze
CLOSED_STATUS_KEYS = %w[done archived].freeze

# --- settings backup -----------------------------------------------------------

# Names whose raw `settings.value` is saved before the seed overwrites it. A nil
# entry means the row did not exist and the teardown deletes it again.
GLOBAL_SETTING_NAMES = %w[plugin_redmine_expert_agile gravatar_enabled
                          force_default_language_for_loggedin ui_theme].freeze

def raw_setting(name)
  Setting.where(:name => name).pick(:value)
end

# Setting.find_or_default raises for a name outside available_settings, and
# Setting#value= serialises against that same registry, so the backup row is
# written through the column rather than through the model.
def write_raw_setting!(name, value)
  unless Setting.where(:name => name).exists?
    row = Setting.new
    row.name = name
    row.save(:validate => false)
  end
  Setting.where(:name => name).update_all(:value => value, :updated_on => Time.current)
end

def load_backup
  raw = raw_setting(BACKUP_KEY)
  raw.blank? ? nil : JSON.parse(raw)
end

def save_backup!(backup)
  write_raw_setting!(BACKUP_KEY, backup.to_json)
end

# --- relabel mode --------------------------------------------------------------

# Renames the demo statuses so the German screenshots get German column headers
# without re-seeding — issue ids, card order and chart shapes stay identical
# across both sets.
if ENV['RELABEL'].present?
  lang = ENV['RELABEL'].to_s
  abort "RELABEL must be 'en' or 'de'" unless STATUS_LABELS.key?(lang)

  backup = load_backup
  abort 'no backup row found — run the seed first' if backup.nil?

  backup['status_ids'].each do |key, id|
    status = IssueStatus.find_by(:id => id)
    next if status.nil?

    name = STATUS_LABELS[lang][key]
    clash = IssueStatus.where(:name => name).where.not(:id => id).exists?
    abort "cannot rename status ##{id} to #{name.inspect}: name already taken" if clash

    status.update!(:name => name)
  end
  say "statuses relabelled to #{lang}: " \
      "#{backup['status_ids'].values.map { |id| IssueStatus.find_by(:id => id)&.name }.compact.join(', ')}"
  exit
end

# --- dry run -------------------------------------------------------------------

# Reports what a re-run would delete and changes nothing.
if ENV['DRY_RUN'].present?
  existing = Project.find_by(:identifier => IDENT)
  if existing.nil?
    say 'DRY RUN — no demo project yet, a run would create one from scratch'
  else
    ids = Issue.where(:project_id => existing.id).pluck(:id)
    say "DRY RUN — would rebuild project ##{existing.id}: #{ids.size} issues, " \
        "#{Journal.where(:journalized_type => 'Issue', :journalized_id => ids).count} journals, " \
        "#{ExpertAgileSprint.where(:project_id => existing.id).count} sprints, " \
        "#{Query.where(:project_id => existing.id).where("type LIKE 'ExpertAgile%'").count} queries, " \
        "#{TimeEntry.where(:project_id => existing.id).count} time entries, " \
        "#{Version.where(:project_id => existing.id).count} versions"
  end
  say "DRY RUN — backup row present: #{load_backup ? 'yes' : 'no'}"
  exit
end

# --- capture user and team -----------------------------------------------------

password = ENV['DEMO_PASSWORD'].presence || SecureRandom.alphanumeric(20)

user = User.find_by(:login => LOGIN) ||
       User.new(:login => LOGIN, :firstname => 'Screenshot', :lastname => 'Demo',
                :mail => 'screenshot-agile-demo@example.com')
user.language = 'en'
user.admin = true
user.must_change_passwd = false
user.status = User::STATUS_ACTIVE
user.password = password
user.password_confirmation = password
user.save!
User.current = user

# Synthetic team. Assignee names sit on every card and label every swimlane, so
# these are invented people — never anyone the installation actually knows.
TEAM = [%w[ada-demo Ada Byron], %w[linus-demo Linus Chen],
        %w[grace-demo Grace Weber], %w[kent-demo Kent Vogel]].freeze

team = TEAM.map do |login, firstname, lastname|
  member = User.find_by(:login => login) ||
           User.new(:login => login, :mail => "#{login}@example.com")
  member.firstname = firstname
  member.lastname = lastname
  member.language = 'en'
  member.status = User::STATUS_ACTIVE
  member.password = SecureRandom.alphanumeric(20) if member.new_record?
  member.save!
  member
end
say "capture user ##{user.id} (#{user.login}), team #{team.map(&:login).join(', ')}"

# --- global rows: trackers, statuses, workflows ---------------------------------

backup = load_backup
# On a re-run the pristine values are already recorded; overwriting them with
# what the previous run wrote would make the teardown restore the seed's own
# settings instead of the installation's.
backup ||= { 'settings' => GLOBAL_SETTING_NAMES.index_with { |name| raw_setting(name) },
             'colors_count' => ExpertAgileColor.count }

status_ids = backup['status_ids'] || {}
tracker_ids = backup['tracker_ids'] || {}

STATUS_LABELS['en'].each_with_index do |(key, name), index|
  status = status_ids[key] && IssueStatus.find_by(:id => status_ids[key])
  if status.nil?
    clash = IssueStatus.find_by(:name => name)
    abort "issue status #{name.inspect} already exists (##{clash.id})" if clash

    status = IssueStatus.create!(:name => name,
                                 :is_closed => CLOSED_STATUS_KEYS.include?(key),
                                 :position => IssueStatus.maximum(:position).to_i + 1 + index)
  end
  status_ids[key] = status.id
end

TRACKER_LABELS.each_with_index do |(key, name), index|
  tracker = tracker_ids[key] && Tracker.find_by(:id => tracker_ids[key])
  if tracker.nil?
    clash = Tracker.find_by(:name => name)
    abort "tracker #{name.inspect} already exists (##{clash.id})" if clash

    tracker = Tracker.create!(:name => name,
                              :default_status_id => status_ids['backlog'],
                              :position => Tracker.maximum(:position).to_i + 1 + index)
  end
  tracker_ids[key] = tracker.id
end

# Board columns render in Redmine's own status order, so the demo statuses have
# to sit in workflow order at the end of the list. The order comes from
# STATUS_LABELS and not from the backup row's key order: a status added by a
# later revision of this script is appended there, and would otherwise position
# itself after "Done".
status_ids = STATUS_LABELS['en'].keys.index_with { |key| status_ids[key] }
base_position = IssueStatus.where.not(:id => status_ids.values).maximum(:position).to_i
status_ids.each_value.with_index do |id, index|
  IssueStatus.where(:id => id).update_all(:position => base_position + index + 1)
end

statuses = status_ids.transform_values { |id| IssueStatus.find(id) }
trackers = tracker_ids.transform_values { |id| Tracker.find(id) }
board_statuses = BOARD_STATUS_KEYS.map { |key| statuses[key] }

role = Role.givable.find_by(:name => 'Manager') || Role.givable.order(:position).first
abort 'no givable role available' if role.nil?

# Every ordered pair of demo statuses, so a card can be dragged anywhere on the
# board. Redmine resolves an admin's allowed transitions against all roles, so
# one role's worth of rows is enough for the capture user — the demo members get
# the same role, so it is enough for them too.
workflow_ids = Array(backup['workflow_ids'])
if workflow_ids.empty?
  rows = trackers.values.flat_map do |tracker|
    statuses.values.flat_map do |from|
      statuses.values.filter_map do |to|
        next if from.id == to.id

        { :type => 'WorkflowTransition', :tracker_id => tracker.id, :role_id => role.id,
          :old_status_id => from.id, :new_status_id => to.id,
          :author => false, :assignee => false }
      end
    end
  end
  WorkflowTransition.insert_all(rows)
  workflow_ids = WorkflowTransition.where(:tracker_id => trackers.values.map(&:id),
                                          :role_id => role.id).pluck(:id)
end

backup['status_ids'] = status_ids
backup['tracker_ids'] = tracker_ids
backup['workflow_ids'] = workflow_ids
save_backup!(backup)
say "demo trackers #{tracker_ids.values.inspect}, statuses #{status_ids.values.inspect}, " \
    "#{workflow_ids.size} workflow transitions"
say "settings backup: #{backup['settings'].to_json}"

# --- project -------------------------------------------------------------------

project = Project.find_by(:identifier => IDENT)
project ||= Project.create!(:name => 'Screenshot Agile', :identifier => IDENT,
                            :is_public => false,
                            :description => 'Demo project used to generate the README screenshots.')
project.enabled_module_names = (project.enabled_module_names |
                                %w[issue_tracking time_tracking expert_agile expert_agile_backlog])
project.trackers = trackers.values
project.save!

([user] + team).each do |principal|
  next if Member.where(:project_id => project.id, :user_id => principal.id).exists?

  Member.create!(:project => project, :user => principal, :roles => [role])
end
say "project ##{project.id} (#{project.identifier})"

# --- wipe ----------------------------------------------------------------------

# Guard first: everything below deletes, and this script is pointed at a
# database that also holds real projects.
abort "refusing to wipe: unexpected project #{project.identifier}" unless project.identifier == IDENT

issue_ids = Issue.where(:project_id => project.id).pluck(:id)
sprint_ids = ExpertAgileSprint.where(:project_id => project.id).pluck(:id)
journal_ids = Journal.where(:journalized_type => 'Issue', :journalized_id => issue_ids).pluck(:id)

# delete_all, never destroy_all: the plugins installed alongside hook Issue and
# Journal callbacks, and a wipe must not fire them.
ExpertAgileData.where(:issue_id => issue_ids).delete_all
ExpertAgileData.where(:sprint_id => sprint_ids).delete_all
ExpertAgileSprint.where(:id => sprint_ids).delete_all
ExpertAgileColor.where(:container_type => 'Issue', :container_id => issue_ids).delete_all
Query.where(:project_id => project.id).where("type LIKE 'ExpertAgile%'").delete_all
TimeEntry.where(:project_id => project.id).delete_all
JournalDetail.where(:journal_id => journal_ids).delete_all
Journal.where(:id => journal_ids).delete_all
Issue.where(:id => issue_ids).delete_all
Version.where(:project_id => project.id).delete_all
say "cleared #{issue_ids.size} previously seeded issues"

# --- global settings -----------------------------------------------------------

Setting.plugin_redmine_expert_agile = (Setting.plugin_redmine_expert_agile || {}).merge(
  'story_points_on' => '1',        # default '0' — story points are invisible otherwise
  'sprints_on' => '1',             # default '0' — the sprint selector is hidden otherwise
  # chart_cache_minutes is deliberately left at its shipped default: the chart
  # cache key fingerprints the scope's count and newest updated_on, so re-seeded
  # data can never be served from a stale entry.
  'estimate_units' => 'story_points',
  'color_base' => 'tracker',
  'status_colors' => '1',
  'default_card_columns' => 'tracker,assigned_to,done_ratio',
  'card_description_length' => '140',
  'sp_values' => '0,1,2,3,5,8,13,20,40,100',
  'trackers_for_sp' => ''
)
# The capture browser must reach no external host, and the English pass needs
# the per-user language to be honoured.
Setting.gravatar_enabled = '0'
Setting.force_default_language_for_loggedin = '0'
Setting.ui_theme = ''
# Redmine keys its settings cache on the newest updated_on, so the running web
# container picks all of this up on its next request — no restart needed.
Setting.clear_cache
say 'global settings written (story points on, sprints on, stock theme, gravatar off)'

# --- sprints and versions ------------------------------------------------------

SPRINT_PLAN = [
  ['Sprint 21', ExpertAgileSprint::STATUS_CLOSED, -50, -37],
  ['Sprint 22', ExpertAgileSprint::STATUS_CLOSED, -36, -23],
  ['Sprint 23', ExpertAgileSprint::STATUS_CLOSED, -22, -9],
  ['Sprint 24', ExpertAgileSprint::STATUS_ACTIVE, -8, 5],
  ['Sprint 25', ExpertAgileSprint::STATUS_OPEN, 6, 19]
].freeze

sprints = SPRINT_PLAN.map do |name, status, from, to|
  ExpertAgileSprint.create!(
    :project => project, :name => name, :status => status,
    :start_date => TODAY_D + from, :end_date => TODAY_D + to,
    :description => "#{name} of the demo team.",
    # One sprint is shared down the tree so the sharing column is not five
    # identical cells.
    :sharing => name == 'Sprint 25' ? ExpertAgileSprint::SHARING_TREE : ExpertAgileSprint::SHARING_NONE
  )
end
sprint_active = sprints[3]
sprint_next = sprints[4]
closed_sprints = sprints[0..2]
say "sprints: #{sprints.map { |s| "#{s.name}/#{s.status_name}" }.join(' ')}"

Version.create!(:project => project, :name => 'Release 2026.2', :status => 'closed',
                :effective_date => TODAY_D - 12)
version_next = Version.create!(:project => project, :name => 'Release 2026.3', :status => 'open',
                               :effective_date => TODAY_D + 28)
Version.create!(:project => project, :name => 'Release 2026.4', :status => 'open',
                :effective_date => TODAY_D + 70)

# --- issue material ------------------------------------------------------------

SUBJECTS = [
  'Split the checkout form into three steps',
  'Search returns stale results after a re-index',
  'Add keyboard shortcuts to the issue list',
  'Session expires while a long form is open',
  'Cache the dashboard aggregation query',
  'Import wizard drops rows with empty columns',
  'Dark mode contrast fails on secondary buttons',
  'Expose the export endpoint in the public API',
  'Password reset link expires too early',
  'Paginate the audit log',
  'Duplicate notifications on bulk edit',
  'Add a bulk assign action to the board',
  'Timezone offset wrong in the weekly report',
  'Reduce the initial bundle size',
  'Attachment upload fails over 20 MB',
  'Introduce a read-only demo role',
  'Sorting by due date ignores empty values',
  'Autocomplete drops the last keystroke',
  'Add per-project retention settings',
  'Migrate the avatar store to object storage',
  'Filter chips wrap badly on narrow screens',
  'Rate limit the public search endpoint',
  'Restore scroll position when going back',
  'CSV export uses the wrong decimal separator',
  'Add an undo step to the archive action',
  'Two-factor setup loses the recovery codes',
  'Group the settings page into sections',
  'Webhook retries hammer a failing endpoint',
  'Support markdown tables in comments',
  'Deleting a category orphans its issues',
  'Add a compact density option to the table',
  'Long project names break the breadcrumb',
  'Warm the report cache after a deploy',
  'Inline images lose their alt text',
  'Add a saved-filter picker to the sidebar',
  'Slow query on the activity page',
  'Draft comments are lost on navigation',
  'Add a print stylesheet for reports',
  'Locale fallback shows raw translation keys',
  'Batch the outgoing mail queue',
  'Sticky table header jitters while scrolling',
  'Validate the webhook signature',
  'Allow reordering of custom fields',
  'Empty state missing on the backlog',
  'Time entries ignore the project default activity',
  'Add a health endpoint for the load balancer',
  'Tooltip overflows the viewport on the right',
  'Reindex job blocks the request queue',
  'Support relative dates in the filter bar',
  'Broken link in the onboarding e-mail',
  'Add column presets to the issue list',
  'Sub-project issues missing from the roll-up',
  'Throttle the autosave requests',
  'Copy-to-clipboard fails in Safari',
  'Add an audit entry for permission changes',
  'Chart legend overlaps the last data point',
  'Split the deployment pipeline into stages',
  'Retry failed avatar uploads in the background',
  'Show the assignee on the mobile card',
  'Document the rate limits in the API guide'
].freeze

BODIES = [
  "Reported by the pilot team.\n\nSteps to reproduce are in the linked notes; it happens on " \
  "every second attempt and only with more than one project selected.",
  "Comes out of the last review round.\n\nThe current behaviour is not wrong, but it costs " \
  "two extra clicks in the most common flow.",
  "Small, self-contained piece of work.\n\nNo migration needed, and the existing test covers " \
  "the happy path already.",
  "Follow-up from the performance session.\n\nThe query itself is fine; the problem is that it " \
  "runs once per row instead of once per page."
].freeze

NOTES = [
  'Reproduced on the staging system — moving it forward.',
  'Discussed in the refinement: we go with the simpler option for now.',
  'Waiting for the design review, everything else is ready.',
  'Split off the API part; this issue only covers the UI.',
  'Verified after the deploy, looks good.'
].freeze

# ActiveRecord's update_columns silently drops a model's own timestamp columns
# (created_on / updated_on on Issue and Journal); update_all writes them.
def backdate!(klass, id, attrs)
  klass.where(:id => id).update_all(attrs)
end

# Places a timestamp inside working hours, bimodal around 09-11 and 14-16.
def business_moment(day)
  hour = rand < 0.55 ? [9, 10, 11].sample : [14, 15, 16].sample
  day.change(:hour => hour, :min => rand(0..59), :sec => rand(0..59))
end

def workday_back(days_ago)
  day = TODAY - days_ago.days
  day -= 1.day while [6, 7].include?(day.to_date.cwday)
  day
end

# One status hop, as the charts read it: a backdated journal carrying a
# status_id (and optionally done_ratio) detail. JournalProjection replays
# exactly these rows, keyed on Journal#created_on — an issue's final state alone
# produces a flat burndown.
def transition!(issue, from_status, to_status, at, actor, done_ratio: nil)
  journal = Journal.new(:journalized => issue, :user => actor)
  journal.notify = false if journal.respond_to?(:notify=)
  journal.save!
  JournalDetail.create!(:journal_id => journal.id, :property => 'attr', :prop_key => 'status_id',
                        :old_value => from_status.id.to_s, :value => to_status.id.to_s)
  if done_ratio
    JournalDetail.create!(:journal_id => journal.id, :property => 'attr', :prop_key => 'done_ratio',
                          :old_value => issue.done_ratio.to_s, :value => done_ratio.to_s)
  end
  backdate!(Journal, journal.id, :created_on => at, :updated_on => at)
  journal
end

def note!(issue, text, at, actor)
  journal = Journal.new(:journalized => issue, :user => actor, :notes => text)
  journal.notify = false if journal.respond_to?(:notify=)
  journal.save!
  backdate!(Journal, journal.id, :created_on => at, :updated_on => at)
end

subject_pool = SUBJECTS.shuffle
subject_index = 0
next_subject = lambda do
  subject = subject_pool[subject_index % subject_pool.size]
  round = subject_index / subject_pool.size
  subject_index += 1
  round.zero? ? subject : "#{subject} (#{round + 1})"
end

# Creates the issue in the backlog status and walks it along the demo workflow
# to `target`, leaving one backdated journal per hop behind.
def seed_issue!(project:, tracker:, author:, assignee:, subject:, statuses:, path:, target:,
                created_at:, closed_at: nil, done_ratio: 0, estimated_hours: nil)
  issue = Issue.new(:project => project, :tracker => tracker, :author => author,
                    :subject => subject, :description => BODIES[rand(BODIES.size)],
                    :status => statuses['backlog'], :assigned_to => assignee,
                    :priority => IssuePriority.active.sorted.to_a[rand(4)] || IssuePriority.default,
                    :estimated_hours => estimated_hours,
                    :start_date => created_at.to_date,
                    :done_ratio => 0)
  issue.save!
  backdate!(Issue, issue.id, :created_on => created_at, :updated_on => created_at)
  issue.reload

  hops = path.take_while { |key| key != target } + [target]
  hops = hops.drop(1) # the issue is already in `path.first`
  span = ((closed_at || TODAY) - created_at).to_i
  step = hops.empty? ? 0 : span / (hops.size + 1)
  current = statuses[path.first]
  at = created_at
  hops.each_with_index do |key, index|
    at = created_at + (step * (index + 1))
    at = closed_at if closed_at && index == hops.size - 1
    transition!(issue, current, statuses[key], at, issue.assigned_to || issue.author)
    current = statuses[key]
  end
  note!(issue, NOTES[rand(NOTES.size)], at, issue.assigned_to || issue.author) if rand < 0.2

  attrs = { :status_id => current.id, :done_ratio => done_ratio, :updated_on => at }
  attrs[:closed_on] = closed_at if closed_at
  backdate!(Issue, issue.id, attrs)
  issue.reload
end

PATH = %w[backlog todo progress review test done].freeze
ARCHIVE_PATH = %w[backlog todo progress review test archived].freeze

tracker_pool = [trackers['story'], trackers['story'], trackers['bug'], trackers['task']].freeze
assignee_pool = (team + [nil, nil]).freeze

# Cohort A — the board. Column sizes are chosen so the grid stays readable and
# so exactly one column sits over its advisory WIP limit.
BOARD_PLAN = { 'todo' => 10, 'progress' => 7, 'review' => 5, 'test' => 4, 'done' => 14 }.freeze

board_issues = []
BOARD_PLAN.each do |target, count|
  count.times do |i|
    # Created before the sprint started and closed inside it, so the burndown
    # starts at the sprint's full commitment and actually descends.
    created = business_moment(workday_back(rand(9..25)))
    closed = target == 'done' ? business_moment(workday_back(rand(0..7))) : nil
    done_ratio = case target
                 when 'todo' then 0
                 when 'progress' then [20, 30, 40, 50, 60, 70].sample
                 when 'review', 'test' then [70, 80, 90].sample
                 else 100
                 end
    board_issues << seed_issue!(
      :project => project, :tracker => tracker_pool[(board_issues.size + i) % tracker_pool.size],
      :author => user, :assignee => assignee_pool[board_issues.size % assignee_pool.size],
      :subject => next_subject.call, :statuses => statuses, :path => PATH, :target => target,
      :created_at => created, :closed_at => closed, :done_ratio => done_ratio,
      :estimated_hours => [2, 3, 4, 6, 8, 12, 16].sample
    )
  end
end
say "board issues: #{board_issues.size}"

# Cohort C — the unplanned backlog the planner drags from. Seeded before the
# release history so that it, like the board, draws from the unused end of the
# subject pool: the two cohorts a reader actually reads carry no duplicates.
backlog_issues = 14.times.map do |i|
  seed_issue!(
    :project => project, :tracker => tracker_pool[i % tracker_pool.size], :author => user,
    :assignee => i.even? ? nil : team[i % team.size], :subject => next_subject.call,
    :statuses => statuses, :path => PATH, :target => 'backlog',
    :created_at => business_moment(workday_back(rand(1..20))),
    :estimated_hours => [2, 3, 4, 6, 8].sample
  )
end
say "backlog issues: #{backlog_issues.size}"

# Cohort B — the release history the charts replay. Spread over the last sixty
# days so burndown, burnup, cumulative flow and velocity all have a shape.
history_issues = []
72.times do |i|
  created_days = rand(20..60)
  closed_days = [created_days - rand(3..14), 1].max
  created = business_moment(workday_back(created_days))
  closed = business_moment(workday_back(closed_days))
  closed = created + 2.days if closed <= created
  history_issues << seed_issue!(
    :project => project, :tracker => tracker_pool[i % tracker_pool.size], :author => user,
    :assignee => team[i % team.size], :subject => next_subject.call, :statuses => statuses,
    :path => ARCHIVE_PATH, :target => 'archived', :created_at => created, :closed_at => closed,
    :done_ratio => 100, :estimated_hours => [2, 3, 4, 6, 8, 12, 16].sample
  )
  say "history #{i + 1}/72" if ((i + 1) % 25).zero?
end
say "history issues: #{history_issues.size}"

# --- agile data: rank, story points, sprint ------------------------------------

SP_VALUES = [1, 2, 3, 5, 8, 13].freeze

rows = []
board_issues.group_by(&:status_id).each_value do |cell|
  cell.each_with_index do |issue, index|
    rows << { :issue_id => issue.id, :position => 1024.0 * (index + 1),
              :story_points => rand < 0.85 ? SP_VALUES.sample : nil,
              :sprint_id => sprint_active.id }
  end
end
history_issues.each_with_index do |issue, index|
  sprint = closed_sprints[[((TODAY_D - issue.closed_on.to_date).to_i / 14), 2].min] || closed_sprints.last
  rows << { :issue_id => issue.id, :position => 1024.0 * (index + 1),
            :story_points => SP_VALUES.sample, :sprint_id => sprint.id }
end
backlog_issues.each_with_index do |issue, index|
  # No sprint: this is exactly what the planner's unplanned lane selects.
  rows << { :issue_id => issue.id, :position => 1024.0 * (index + 1),
            :story_points => rand < 0.7 ? SP_VALUES.sample : nil, :sprint_id => nil }
end
rows.each_slice(500) { |slice| ExpertAgileData.insert_all(slice) }
say "agile data rows: #{rows.size}"

# A handful of next-sprint and next-version commitments, so the planner shows
# populated lanes rather than one full backlog and four empty targets.
ExpertAgileData.where(:issue_id => backlog_issues.first(5).map(&:id))
               .update_all(:sprint_id => sprint_next.id)
Issue.where(:id => backlog_issues.last(4).map(&:id)).update_all(:fixed_version_id => version_next.id)

# --- time entries --------------------------------------------------------------

activity = TimeEntryActivity.where(:project_id => nil).active.order(:position).first
if activity
  entries = (board_issues + history_issues).sample(60).map do |issue|
    { :project_id => project.id, :issue_id => issue.id, :user_id => user.id, :author_id => user.id,
      :activity_id => activity.id, :hours => [0.5, 1.0, 1.5, 2.0, 3.0, 4.0].sample,
      :spent_on => (issue.closed_on || issue.created_on).to_date, :comments => '',
      :created_on => TODAY, :updated_on => TODAY, :tyear => TODAY_D.year,
      :tmonth => TODAY_D.month, :tweek => TODAY_D.cweek }
  end
  entries.each_slice(200) { |slice| TimeEntry.insert_all(slice) }
  say "time entries: #{entries.size}"
end

# --- card colours ---------------------------------------------------------------

# Only the demo containers are coloured — never the installation's own trackers
# and statuses, which the teardown would then have to guess at.
{ 'story' => 'blue', 'bug' => 'red', 'task' => 'green' }.each do |key, color|
  ExpertAgileColor.find_or_initialize_by(:container_type => 'Tracker',
                                         :container_id => trackers[key].id).update!(:color => color)
end
{ 'backlog' => 'gray', 'todo' => 'blue', 'progress' => 'orange', 'review' => 'purple',
  'test' => 'yellow', 'done' => 'green' }.each do |key, color|
  ExpertAgileColor.find_or_initialize_by(:container_type => 'IssueStatus',
                                         :container_id => statuses[key].id).update!(:color => color)
end

# --- saved boards and charts -----------------------------------------------------

# Filter on every status, not the default "open": the Done column is a closed
# status, and an open-only board renders it permanently empty.
ALL_STATUSES = { 'status_id' => { :operator => '*', :values => [''] } }.freeze

board = ExpertAgileQuery.new(:name => 'Sprint board', :project => project, :user => user,
                             :visibility => Query::VISIBILITY_PUBLIC)
board.filters = ALL_STATUSES.deep_dup
board.column_names = %i[tracker assigned_to done_ratio]
board.board_status_ids = board_statuses.map(&:id)
board.wip_limits = { statuses['progress'].id => [2, 8], statuses['review'].id => [nil, 4],
                     statuses['test'].id => [nil, 6] }
board.color_base = 'tracker'
board.board_type = 'scrum'
board.show_avatar = '0'
board.save!

lanes = ExpertAgileQuery.new(:name => 'Sprint board by assignee', :project => project, :user => user,
                             :visibility => Query::VISIBILITY_PUBLIC)
lanes.filters = ALL_STATUSES.deep_dup
lanes.column_names = %i[tracker done_ratio day_in_state]
lanes.board_status_ids = board_statuses.map(&:id)
lanes.wip_limits = board.wip_limits
lanes.color_base = 'status'
lanes.board_type = 'scrum'
lanes.show_avatar = '0'
lanes.swimlane_field = 'assigned_to'
lanes.save!

mine = ExpertAgileQuery.new(:name => 'My open bugs', :project => project, :user => user,
                            :visibility => Query::VISIBILITY_PRIVATE)
mine.filters = { 'status_id' => { :operator => 'o', :values => [''] },
                 'tracker_id' => { :operator => '=', :values => [trackers['bug'].id.to_s] } }
mine.column_names = %i[tracker assigned_to]
mine.board_status_ids = board_statuses.map(&:id)
mine.color_base = 'priority'
mine.save!

def chart_query!(project, user, name, chart, unit, interval, from, to, filters = nil)
  query = ExpertAgileChartsQuery.new(:name => name, :project => project, :user => user,
                                     :visibility => Query::VISIBILITY_PUBLIC)
  query.filters = filters || { 'status_id' => { :operator => '*', :values => [''] } }
  query.chart = chart
  query.chart_unit = unit
  query.interval = interval
  query.date_from = from.to_s
  query.date_to = to.to_s
  query.save!
  query
end

# A sprint burndown has to name its issues explicitly: charts are scoped by
# ordinary issue filters, and the plugin has no sprint filter — a sprint is a
# row in its own table, not an issue attribute Redmine's query layer knows.
burndown = chart_query!(project, user, 'Sprint 24 burndown', 'burndown', 'story_points', 'day',
                        sprint_active.start_date, sprint_active.end_date,
                        'issue_id' => { :operator => '=',
                                        :values => [board_issues.map(&:id).join(',')] })
velocity = chart_query!(project, user, 'Velocity, last 60 days', 'velocity', 'issues', 'week',
                        TODAY_D - 59, TODAY_D)
flow = chart_query!(project, user, 'Cumulative flow, last 60 days', 'cumulative_flow', 'issues',
                    'day', TODAY_D - 59, TODAY_D)

say "saved boards: #{[board, lanes, mine].map(&:id).inspect}, " \
    "charts: #{[burndown, velocity, flow].map(&:id).inspect}"

# --- summary ---------------------------------------------------------------------

base = 'http://localhost:3000'
say 'done.'
say "capture user #{LOGIN} password=#{password}"
say "board       #{base}/projects/#{IDENT}/expert_agile/board?query_id=#{board.id}"
say "swimlanes   #{base}/projects/#{IDENT}/expert_agile/board?query_id=#{lanes.id}"
say "backlog     #{base}/projects/#{IDENT}/expert_agile/backlog"
say "sprints     #{base}/projects/#{IDENT}/settings/expert_agile_sprints"
say "burndown    #{base}/projects/#{IDENT}/expert_agile/charts?query_id=#{burndown.id}"
say "velocity    #{base}/projects/#{IDENT}/expert_agile/charts?query_id=#{velocity.id}"
say "flow        #{base}/projects/#{IDENT}/expert_agile/charts?query_id=#{flow.id}"
say 'restore the instance with scripts/teardown_screenshot_demo.rb when the shots are taken'
