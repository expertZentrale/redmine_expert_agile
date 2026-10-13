# Completing a sprint, Jira style: its open issues move on — to another
# sprint or back to the backlog — the sprint closes, and the sprint they moved
# to can take over as the active one. All of it or none of it.
#
# A sprint cannot be closed while it holds open issues (closing one would
# rewrite its burndown after the fact), so without this the team drags every
# leftover out by hand, then closes the sprint, then activates the next one —
# and a board following the active sprint is empty whenever that is half
# done.
#
# Every issue moves the way the backlog planner moves it: through its agile
# data row, with a journal entry, under the planner's permission and the
# issue's own validation (the target has to be a sprint the issue's project
# may plan into). One refusal and nothing is written; the caller gets every
# refusal at once, not the first.
module RedmineExpertAgile
  class SprintCompletion
    TARGET_NEXT = 'next'.freeze
    TARGET_BACKLOG = 'backlog'.freeze
    TARGET_NEW = 'new'.freeze

    # One issue that could not be moved, and why.
    Refusal = Struct.new(:issue, :reason)

    attr_reader :sprint, :user, :refusals, :new_sprint, :moved

    def initialize(sprint, user = User.current)
      @sprint = sprint
      @user = user
      @refusals = []
      @moved = []
    end

    # The sprint's open issues, the ones that have to go somewhere.
    def open_issues
      sprint.issues.open.order(:id).to_a
    end

    # What the page and the preview show: only issues the user may see. A
    # shared sprint holds other projects' issues too, and their number is
    # nobody's business here (the sprint API counts the same way). The move
    # itself still covers every open issue, and refuses on one it cannot see.
    def visible_open_issues
      open_issues.select { |issue| issue.visible?(user) }
    end

    def closed_issue_count
      sprint.issues.visible(user).joins(:status).where(IssueStatus.table_name => { :is_closed => true }).count
    end

    def points(issues)
      ExpertAgileData.where(:issue_id => issues.map(&:id)).sum(:story_points).to_i
    end

    # The open sprint that follows this one: the next one by start date the
    # sprint's project may plan into.
    def next_sprint
      @next_sprint ||= sprint.project.shared_expert_agile_sprints.open
                             .where.not(:id => sprint.id)
                             .where("#{ExpertAgileSprint.table_name}.start_date >= ?", sprint.start_date)
                             .reorder(:start_date, :id).first
    end

    # Name and dates for a sprint created on the spot: the same length,
    # starting the day after the project's last planned sprint ends, and the
    # name counted up to the first one not taken ("Sprint 4" with a "Sprint
    # 5" already planned → "Sprint 6"). A name without a number gets one.
    def suggested_new_sprint_attributes
      length = (sprint.end_date - sprint.start_date).to_i
      # Names are unique per project regardless of case.
      taken = sprint.project.expert_agile_sprints.pluck(:name).map { |name| name.to_s.downcase }
      last_end = sprint.project.expert_agile_sprints.maximum(:end_date) || sprint.end_date
      start = [sprint.end_date, last_end].max + 1
      base, number = sprint.name.to_s =~ /\A(.*?)(\d+)\s*\z/ ? [Regexp.last_match(1), Regexp.last_match(2).to_i] : ["#{sprint.name} ", 1]
      number += 1
      number += 1 while taken.include?("#{base}#{number}".downcase)
      { :name => "#{base}#{number}", :start_date => start, :end_date => start + length }
    end

    # Runs the completion. `target` is TARGET_NEXT, TARGET_BACKLOG,
    # TARGET_NEW (with `new_sprint_attributes`) or a sprint id. Returns true
    # when the sprint is closed; otherwise `refusals` (per issue) or the
    # sprint's and new sprint's errors say why, and nothing was written.
    def complete(target, activate: false, new_sprint_attributes: {})
      @refusals = []
      @moved = []
      ok = false
      ExpertAgileSprint.transaction do
        destination = resolve_target(target, new_sprint_attributes)
        raise ActiveRecord::Rollback if destination == :invalid

        # The sprint and an existing target are locked together, in id order,
        # and read again under the lock. Together: two completions of one
        # sprint would otherwise both find it open and both move its issues.
        # In id order: completing A into B while B is completed into A would
        # otherwise have each request hold one row and wait for the other.
        # Read again: the target was looked up before the lock, and another
        # request may have closed it, or activated another sprint, since.
        existing_target = destination && destination != @new_sprint ? destination : nil
        # Every activation locks the project first and its sprints after
        # (ExpertAgileSprint#deactivate_sibling_sprints). Activating here
        # follows the same order, or it could hold the sprints while another
        # activation holds the project and waits for them.
        Project.lock.where(:id => destination.project_id).pluck(:id) if activate && destination
        locked = ExpertAgileSprint.lock.where(:id => [sprint.id, existing_target && existing_target.id].compact)
                                  .order(:id).pluck(:id)
        # Either row may have been deleted in between; that is a refusal,
        # not an error.
        unless locked.include?(sprint.id)
          sprint.errors.add(:base, ::I18n.t(:error_expert_agile_sprint_complete_gone))
          raise ActiveRecord::Rollback
        end
        if existing_target && !locked.include?(existing_target.id)
          invalid_target
          raise ActiveRecord::Rollback
        end
        sprint.reload
        if sprint.closed?
          sprint.errors.add(:base, ::I18n.t(:error_expert_agile_sprint_already_closed))
          raise ActiveRecord::Rollback
        end
        if existing_target
          existing_target.reload
          unless existing_target.open? || existing_target.active?
            invalid_target
            raise ActiveRecord::Rollback
          end
        end

        open_issues.each { |issue| move(issue, destination) }
        raise ActiveRecord::Rollback if @refusals.any?

        sprint.status = ExpertAgileSprint::STATUS_CLOSED
        raise ActiveRecord::Rollback unless sprint.save

        if activate && destination
          # A sprint shared in from another project is that project's to
          # start; activating it also stands that project's running sprint
          # down.
          unless user.allowed_to?(:manage_expert_agile_sprints, destination.project)
            sprint.errors.add(:base, ::I18n.t(:error_expert_agile_sprint_complete_activate_foreign))
            raise ActiveRecord::Rollback
          end
          destination.status = ExpertAgileSprint::STATUS_ACTIVE
          unless destination.save
            sprint.errors.add(:base, destination.errors.full_messages.join(', '))
            raise ActiveRecord::Rollback
          end
        end
        @destination = destination
        ok = true
      end
      unless ok
        # The rollback undid the database, not the objects: put the sprint
        # back as it was, so the page shows it as it still is.
        sprint.status = sprint.status_was if sprint.status_changed?
        @moved = []
      end
      ok
    end

    # Where the open issues went: a sprint, or nil for the backlog.
    attr_reader :destination

    private

    def resolve_target(target, attributes)
      case target.to_s
      when TARGET_BACKLOG
        nil
      when TARGET_NEXT
        next_sprint || invalid_target
      when TARGET_NEW
        @new_sprint = sprint.project.expert_agile_sprints.build
        @new_sprint.safe_attributes = (attributes || {}).to_h.stringify_keys.slice('name', 'start_date', 'end_date')
        @new_sprint.status = ExpertAgileSprint::STATUS_OPEN
        @new_sprint.save ? @new_sprint : :invalid
      else
        found = sprint.project.shared_expert_agile_sprints.available
                      .where.not(:id => sprint.id).find_by(:id => target.to_s.to_i)
        found || invalid_target
      end
    end

    def invalid_target
      sprint.errors.add(:base, ::I18n.t(:error_expert_agile_sprint_complete_target))
      :invalid
    end

    def move(issue, destination)
      # Issues the user cannot see are refused together, once: one entry per
      # hidden issue would tell how many there are.
      unless issue.visible?(user)
        unless @refusals.any? { |refusal| refusal.issue.nil? }
          @refusals << Refusal.new(nil, ::I18n.t(:error_expert_agile_sprint_complete_issue_hidden))
        end
        return
      end
      reason = refusal_reason(issue)
      return @refusals << Refusal.new(issue, reason) if reason

      issue.init_journal(user)
      issue.expert_agile_data!.sprint_id = destination && destination.id
      if issue.save
        @moved << issue
      else
        @refusals << Refusal.new(issue, issue.errors.full_messages.join(', ').presence ||
                                        ::I18n.t(:error_expert_agile_move_failed))
      end
    end

    # The planner's rules: the user may see the issue, may plan in its
    # project, and may set the field on it at all.
    def refusal_reason(issue)
      return ::I18n.t(:error_expert_agile_sprint_complete_issue_hidden) unless issue.visible?(user)
      unless issue.expert_agile_sprint_editable_by?(user) && issue.safe_attribute?('expert_agile_data_attributes', user)
        return ::I18n.t(:error_expert_agile_sprint_not_editable)
      end

      nil
    end
  end
end
