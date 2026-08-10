# One column of the board: an issue status plus the aggregates and WIP state
# that the header renders.
#
# A plain value object on purpose. RedmineUP stuffs instance variables and
# *defines singleton methods* onto each IssueStatus record inside a loop
# (`def s.over_wp_limit?` ...), which invalidates Ruby's method cache on every
# board render and makes the status objects impossible to cache or compare.
module RedmineExpertAgile
  class BoardColumn
    attr_reader :status, :issue_count, :estimated_hours, :story_points, :wip_min, :wip_max

    def initialize(status:, issue_count: 0, estimated_hours: nil, story_points: nil,
                   wip_min: nil, wip_max: nil)
      @status = status
      @issue_count = issue_count.to_i
      @estimated_hours = estimated_hours
      @story_points = story_points
      @wip_min = wip_min
      @wip_max = wip_max
    end

    def id
      status.id
    end

    def name
      status.name
    end

    def closed?
      status.is_closed?
    end

    # Sub-columns are a naming convention, not a schema: statuses sharing a
    # "Prefix: " prefix nest under one parent header. `path` is the split form,
    # so ["Dev", "Review"] for a status named "Dev: Review".
    def path
      name.to_s.split(':').map(&:strip).reject(&:empty?)
    end

    def leaf_name
      path.last || name.to_s
    end

    # WIP limits are advisory — they colour the header, they never block a move.
    def over_wip_limit?
      wip_max.present? && issue_count > wip_max
    end

    def under_wip_limit?
      wip_min.present? && issue_count < wip_min
    end

    def wip_limit?
      wip_min.present? || wip_max.present?
    end

    def wip_css_class
      return 'ea-wip-over' if over_wip_limit?
      return 'ea-wip-under' if under_wip_limit?

      nil
    end

    def wip_label
      return nil unless wip_limit?

      [wip_min, wip_max].map { |v| v.presence || '' }.join('-').sub(/\A-/, '').sub(/-\z/, '')
    end

    # Serialised into the board's JSON island for the drag & drop script.
    def to_h
      {
        :id => id,
        :name => name,
        :closed => closed?,
        :issue_count => issue_count,
        :wip_min => wip_min,
        :wip_max => wip_max,
        :over_wip_limit => over_wip_limit?
      }
    end
  end
end
