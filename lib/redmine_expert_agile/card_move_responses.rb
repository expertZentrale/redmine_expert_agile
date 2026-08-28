module RedmineExpertAgile
  # Every answer a dragged card gets has to be JSON the board can read.
  #
  # Redmine renders every refusal it owns through `render_error`, which answers
  # anything that is not HTML with `head <status>` — no body at all. The board
  # reads each answer as JSON and, finding nothing, falls back to its own "the
  # move could not be saved". So a missing permission, an expired session, a
  # stale CSRF token and a board that had been deleted all reached the user as
  # the same sentence, and none of them as the reason. That is a bad message for
  # the user and a worse one for whoever they report it to, because it looks
  # like a defect in the board every time.
  #
  # These overrides give each of those a body. They apply only to the drag &
  # drop format; every other request keeps Redmine's own behaviour, so the
  # board page itself still renders Redmine's error pages.
  #
  # A controller including this must provide `render_card_move_refusal(message,
  # status)`, which is where its own JSON shape is built.
  module CardMoveResponses
    # Wraps the action only, so the before_action refusals above still take the
    # paths Redmine has for them — `deny_access` and friends land in the
    # overrides below.
    def self.included(base)
      base.around_action :answer_card_move_failures_with_json
    end

    private

    # Anything unforeseen is still a refusal the user has to be told about. It
    # used to leave Rails to render its 500 page, which is HTML, so it arrived
    # as the generic message with the actual cause visible only in the log —
    # and only to someone who knew to look. The exception is logged here in
    # full and then answered in the board's own shape.
    def answer_card_move_failures_with_json
      yield
    rescue ::Unauthorized, ::ActionView::MissingTemplate
      # Redmine has handlers for these two; let them run.
      raise
    rescue StandardError => e
      raise unless request.format.js?
      raise if performed?

      logger&.error("[expert_agile] #{e.class}: #{e.message}\n  " \
                    "#{Array(e.backtrace).first(20).join("\n  ")}")
      render_card_move_refusal(l(:error_expert_agile_move_failed_unexpectedly),
                               :internal_server_error)
    end

    def render_403(options = {})
      return super unless request.format.js?

      render_card_move_refusal(l(:error_expert_agile_move_not_permitted), :forbidden)
      false
    end

    # Reached when the card, its project or the saved board behind it is gone —
    # including a board deleted while the page that names it was still open.
    def render_404(options = {})
      return super unless request.format.js?

      render_card_move_refusal(l(:error_expert_agile_move_target_gone), :not_found)
      false
    end

    # A session that ran out while the board sat open. Redmine answers with a
    # bare 401, which is exactly the case the board could not explain: the page
    # still looks signed in, so "the move could not be saved" reads as a broken
    # board rather than as "sign in again".
    def require_login
      return super unless request.format.js?
      return true if User.current.logged?

      render_card_move_refusal(l(:error_expert_agile_session_expired), :unauthorized)
      false
    end

    # Same case seen from the other side: the page was loaded before the
    # session was replaced, so its CSRF token no longer matches. Redmine treats
    # that as a session it can no longer trust and signs the user out — kept
    # here, because only the empty 422 it renders is the problem.
    def handle_unverified_request
      return super unless request.format.js?

      cookies.delete(autologin_cookie_name)
      self.logged_user = nil
      set_localization
      render_card_move_refusal(l(:error_expert_agile_session_expired), :unprocessable_entity)
    end
  end
end
