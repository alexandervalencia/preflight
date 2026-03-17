Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "local_repositories#index"

  # Repository management (keep existing paths)
  resources :repositories, controller: "local_repositories", only: [:new, :create]
  get "browse", to: "local_repositories#browse"

  # GitHub-style routes scoped under repository name
  scope "/:repository_name" do
    get "pulls", to: "pull_requests#index", as: :repository_pulls
    get "compare", to: "pull_requests#compare", as: :repository_compare
    post "pulls", to: "pull_requests#create"

    scope "/pull/:id", controller: "pull_requests" do
      get "/", action: :show, as: :repository_pull
      patch "/", action: :update
    end

    get "pull/:id/files", to: "pull_request_files#index", as: :repository_pull_files

    scope "/pull/:pull_request_id" do
      get "commits", to: "pull_request_commits#index", as: :repository_pull_commits
      get "commits/:id", to: "pull_request_commits#show", as: :repository_pull_commit
    end

    post "pull/:id/uploads", to: "uploads#create", as: :repository_pull_uploads
    post "pull/:id/github_export", to: "github_exports#create", as: :repository_pull_github_export
  end

  get "/_preflight/uploads/:pull_request_id/:filename", to: "uploads#show", as: :preflight_upload,
    constraints: { filename: /[^\/]+/ }

  namespace :api do
    resources :pull_requests, only: [:create, :index]
    get "status", to: "pull_requests#status"
  end
end
