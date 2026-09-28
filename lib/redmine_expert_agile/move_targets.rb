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
    end

    # Loads what `closable?` reads for every card in one go. Without it each
    # card asks for its blocking relations on its own.
    def preload(issues)
      issues = issues.to_a
      return self if issues.empty?

      associations = { :relations_to => { :issue_from => :status } }
      preloader = ActiveRecord::Associations::Preloader
      if preloader.instance_method(:initialize).arity.zero?
        preloader.new.preload(issues, associations) # Rails 6.1 (Redmine 5.x)
      else
        preloader.new(:records => issues, :associations => associations).call
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

      key += [assignee?(issue), issue.closable?, issue.reopenable?]
      memo(@allowed, key) do
        ((issue.new_statuses_allowed_to(@user).map(&:id) & @column_ids) | [issue.status_id]).sort
      end
    end

    private

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
