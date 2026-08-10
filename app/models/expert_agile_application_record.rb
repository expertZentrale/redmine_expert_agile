# Shared abstract base class for the plugin models.
#
# Redmine 6+ defines `ApplicationRecord` and mixes the `acts_as_*` DSLs in
# there; Redmine 5.x has no `ApplicationRecord` and mixes them into
# `ActiveRecord::Base`. Picking the right base per version keeps the models
# working under both.
class ExpertAgileApplicationRecord < (defined?(ApplicationRecord) ? ApplicationRecord : ActiveRecord::Base)
  self.abstract_class = true
end
