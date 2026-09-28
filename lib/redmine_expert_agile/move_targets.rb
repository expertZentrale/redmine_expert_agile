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
  # those calls runs its own workflow queries, so plain cards share answers:
  # memoised on everything core's answer depends on for them — the project
  # (the user's roles), the tracker, the status, and whether the user is
  # author or assignee. A board of a few trackers and statuses costs a handful
  # of workflow queries, not two per card.
  #
  # Cards in a hierarchy or a blocking relation are never memoised: whether
  # they may be closed or reopened depends on other issues, and deriving that
  # here would be a second copy of core's rules that can drift from it. They
  # are asked one by one, through core, which is what the server does.
  class MoveTargets
    def initialize(user, column_ids)
      @user = user
      @column_ids = column_ids
      @editable = {}
      @status_editable = {}
      @allowed = {}
    end

    # Loads the blocking relations core's `closable?` reads, so telling a plain
    # card from a related one costs no query per card.
    def preload(issues)
      issues = issues.to_a
      return self if issues.empty?

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

      return allowed_for(issue) unless plain?(issue)

      memo(@allowed, key + [assignee?(issue)]) { allowed_for(issue) }
    end

    private

    def allowed_for(issue)
      ((issue.new_statuses_allowed_to(@user).map(&:id) & @column_ids) | [issue.status_id]).sort
    end

    # No subtasks, no parent, not on the receiving end of a relation: nothing
    # outside the issue itself can make core's closable? or reopenable? false.
    def plain?(issue)
      issue.leaf? && issue.parent_id.nil? && issue.relations_to.empty?
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
