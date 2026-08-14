# Routes for redmine_expert_agile.
#
# Everything is namespaced under /expert_agile so nothing collides with the
# RedmineUP plugin's /agile routes while both are installed.
#
# Note the board update route carries the issue id in the path. RedmineUP uses
# `PUT /agile/board` with the id in the body, which cannot be authorised or
# cached at the routing layer.
RedmineApp::Application.routes.draw do
  # --- Board ------------------------------------------------------------
  get 'projects/:project_id/expert_agile/board', :to => 'expert_agile_boards#index',
      :as => 'project_expert_agile_board'
  get 'expert_agile/board', :to => 'expert_agile_boards#index',
      :as => 'expert_agile_board'

  put 'expert_agile/board/issues/:id', :to => 'expert_agile_boards#update',
      :as => 'update_expert_agile_board_issue'
  post 'projects/:project_id/expert_agile/board/issues', :to => 'expert_agile_boards#create_issue',
       :as => 'create_expert_agile_board_issue'
  get 'expert_agile/board/issues/:id/edit', :to => 'expert_agile_boards#edit_issue',
      :as => 'edit_expert_agile_board_issue'
  patch 'expert_agile/board/issues/:id', :to => 'expert_agile_boards#update_issue',
        :as => 'update_expert_agile_board_issue_fields'
  get 'expert_agile/board/issues/:id/tooltip', :to => 'expert_agile_boards#issue_tooltip',
      :as => 'expert_agile_board_issue_tooltip'

  # --- Charts -----------------------------------------------------------
  get 'projects/:project_id/expert_agile/charts', :to => 'expert_agile_charts#show',
      :as => 'project_expert_agile_charts'
  get 'expert_agile/charts', :to => 'expert_agile_charts#show',
      :as => 'expert_agile_charts'
  get 'expert_agile/charts/render_chart', :to => 'expert_agile_charts#render_chart',
      :as => 'render_expert_agile_chart'

  # --- Backlog ----------------------------------------------------------
  get 'projects/:project_id/expert_agile/backlog', :to => 'expert_agile_backlogs#index',
      :as => 'project_expert_agile_backlog'
  put 'projects/:project_id/expert_agile/backlog/issues/:id', :to => 'expert_agile_backlogs#update',
      :as => 'update_expert_agile_backlog_issue'
  get 'projects/:project_id/expert_agile/backlog/load_more', :to => 'expert_agile_backlogs#load_more',
      :as => 'load_more_expert_agile_backlog'
  get 'projects/:project_id/expert_agile/backlog/autocomplete', :to => 'expert_agile_backlogs#autocomplete',
      :as => 'autocomplete_expert_agile_backlog'

  # --- Saved boards / chart / backlog queries ---------------------------
  resources :expert_agile_queries, :except => [:show]
  resources :expert_agile_charts_queries, :except => [:show]
  resources :expert_agile_backlog_queries, :except => [:show]
  resources :projects, :only => [] do
    resources :expert_agile_queries, :only => [:index, :new, :create]
    resources :expert_agile_charts_queries, :only => [:index, :new, :create]
    resources :expert_agile_backlog_queries, :only => [:index, :new, :create]

    # --- Sprints --------------------------------------------------------
    resources :expert_agile_sprints
  end

  # --- Colors -----------------------------------------------------------
  get  'expert_agile/colors/:container_type', :to => 'expert_agile_colors#index',
       :as => 'expert_agile_colors'
  put  'expert_agile/colors/:container_type', :to => 'expert_agile_colors#update',
       :as => 'update_expert_agile_colors'

  # --- REST API ---------------------------------------------------------
  # Read and write agile data for one issue. RedmineUP exposes read only, so
  # story points and sprint assignment can only be set through nested issue
  # attributes; this endpoint makes it a first-class operation.
  # Spelled out rather than nested in a `member` block: the GET and the PUT
  # share a path, and two auto-named routes on the same path raise
  # "Invalid route name, already in use".
  get 'issues/:id/expert_agile_data', :to => 'expert_agile_boards#agile_data',
      :as => 'issue_expert_agile_data'
  put 'issues/:id/expert_agile_data', :to => 'expert_agile_boards#update_agile_data',
      :as => 'update_issue_expert_agile_data'
end
