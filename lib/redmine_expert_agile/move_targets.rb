module RedmineExpertAgile
  # The status columns one card may be dropped into, for the user looking at
  # the board. The board marks every column allowed or blocked the moment a
  # card is picked up, so a move the workflow forbids is visibly impossible
  # instead of being refused after the drop.
  #
  # The answer is built from exactly the calls ExpertAgileBoardsController#update
  # enforces with — `editable?`, `safe_attribute?('status_id')` and
  # `new_statuses_allowed_to` — so the preview and the refusal cannot disagree.
  # Only the server decides; this is what it is going to decide, shown early.
  #
  # Asked for every card on a board of up to `board_items_limit` cards. Each of
  # those calls runs its own workflow queries, so the answers are memoised on
  # everything core's answer depends on: the project (the user's roles), the
  # tracker, the status, whether the user is author or assignee, and whether
  # the issue may be closed or reopened at all. A board of a few trackers and
  # statuses costs a handful of workflow queries, not two per card.
  class MoveTargets
    def initialize(user, column_ids)
      @user = user
      @column_ids = column_ids
      @editable = {}
      @status_editable = {}
      @allowed = {}
      @hierarchy = {}
    end

    # Loads what `closable?` and `reopenable?` read for every card in one go:
    # blocking relations, which parents still have an open subtask and which
    # subtasks sit under a closed ancestor. Without it every card that is
    # blocked, a parent or a subtask asks on its own.
    def preload(issues)
      issues = issues.to_a
      return self if issues.empty?

      open_below = parents_with_open_descendants(issues)
      closed_above = issues_with_closed_ancestors(issues)
      issues.each do |issue|
        @hierarchy[issue.id] = [open_below.include?(issue.id), closed_above.include?(issue.id)]
      end

      associations = { :relations_to => { :issue_from => :status } }
      preloader = ActiveRecord::Associations::Preloader
      # Decided by version, not by probing the constructor: Rails 6.1's takes
      # an optional keyword too, so an arity test picked the 7.0 call there.
      if ActiveRecord.version >= Gem::Version.new('7.0')
        preloader.new(:records => issues, :associations => associations).call
      else
        preloader.new.preload(issues, associations) # Rails 6.1 (Redmine 5.x)
      end
      self
    end

    # Ids of the board columns the card may be dropped into, its own included
    # (a reorder inside the column is a move too). Empty when the user may not
    # touch the issue at all — the server refuses even a reorder then.
    def status_ids_for(issue)
      key = [issue.project_id, issue.tracker_id, issue.status_id, issue.author_id == @user.id]
      return [] unless memo(@editable, key) { issue.editable?(@user) }
      return [issue.status_id] unless memo(@status_editable, key) { issue.safe_attribute?('status_id', @user) }

      key += [assignee?(issue), closable?(issue), reopenable?(issue)]
      memo(@allowed, key) do
        ((issue.new_statuses_allowed_to(@user).map(&:id) & @column_ids) | [issue.status_id]).sort
      end
    end

    private

    # The same answers as Issue#closable? and #reopenable?, from the batches
    # `preload` loaded. They only pick the memo key; the list itself always
    # comes from core's new_statuses_allowed_to. A card that was not preloaded
    # asks core directly.
    def closable?(issue)
      return issue.closable? unless @hierarchy.key?(issue.id)

      !@hierarchy[issue.id][0] && !issue.blocked?
    end

    def reopenable?(issue)
      return issue.reopenable? unless @hierarchy.key?(issue.id)

      !@hierarchy[issue.id][1]
    end

    # Ids of the parents among `issues` with at least one open descendant —
    # core's `descendants.open.any?`. Leaves have no descendants to ask about.
    def parents_with_open_descendants(issues)
      ids = issues.reject(&:leaf?).map(&:id)
      return [] if ids.empty?

      table = Issue.table_name
      Issue.joins("INNER JOIN #{table} below ON below.root_id = #{table}.root_id " \
                  "AND below.lft > #{table}.lft AND below.rgt < #{table}.rgt")
           .joins("INNER JOIN #{IssueStatus.table_name} below_status ON below_status.id = below.status_id")
           .where(:id => ids)
           .where('below_status.is_closed = ?', false)
           .distinct.pluck(:id)
    end

    # Ids of the subtasks among `issues` with a closed ancestor — core's
    # `ancestors.open(false).any?`. Root issues have no ancestors to ask about.
    def issues_with_closed_ancestors(issues)
      ids = issues.select(&:parent_id).map(&:id)
      return [] if ids.empty?

      table = Issue.table_name
      Issue.joins("INNER JOIN #{table} above ON above.root_id = #{table}.root_id " \
                  "AND above.lft < #{table}.lft AND above.rgt > #{table}.rgt")
           .joins("INNER JOIN #{IssueStatus.table_name} above_status ON above_status.id = above.status_id")
           .where(:id => ids)
           .where('above_status.is_closed = ?', true)
           .distinct.pluck(:id)
    end

    def memo(store, key)
      store.key?(key) ? store[key] : (store[key] = yield)
    end

    # Mirrors core's own test: assignee transitions apply to the assignee and
    # to every member of an assigned group.
    def assignee?(issue)
      issue.assigned_to_id.present? &&
        (issue.assigned_to_id == @user.id || @user.group_ids.include?(issue.assigned_to_id))
    end
  end
end
