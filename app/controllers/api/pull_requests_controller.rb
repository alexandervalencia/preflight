class Api::PullRequestsController < ApplicationController
  skip_forgery_protection

  def status
    render json: { status: "ok" }
  end

  def index
    repo = LocalRepository.find_by(path: params[:repo_path])
    return head :not_found unless repo

    pr = repo.pull_requests.open.find_by(source_branch: params[:source_branch])
    return head :not_found unless pr

    render json: {
      url: pull_request_path_for(repo, pr),
      repository_name: repo.name,
      pull_request_id: pr.id
    }
  end

  def create
    repo_path = params[:repo_path]
    source_branch = params[:source_branch]
    base_branch = params[:base_branch]

    local_repository = LocalRepository.find_by(path: repo_path) || register_repository(repo_path)
    return render_error("Repository could not be registered") unless local_repository&.persisted?

    existing = local_repository.pull_requests.open.find_by(source_branch:)
    if existing
      return render json: {
        url: pull_request_path_for(local_repository, existing),
        repository_name: local_repository.name,
        pull_request_id: existing.id,
        created: false
      }, status: :ok
    end

    pull_request = local_repository.pull_requests.new(
      source_branch:,
      base_branch: base_branch.presence || local_repository.default_branch
    )

    if pull_request.save
      render json: {
        url: pull_request_path_for(local_repository, pull_request),
        repository_name: local_repository.name,
        pull_request_id: pull_request.id,
        created: true
      }, status: :created
    else
      render json: { errors: pull_request.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def register_repository(path)
    repo = LocalRepository.new(path:)
    repo.save ? repo : nil
  end

  def pull_request_path_for(repository, pull_request)
    repository_pull_path(repository, pull_request)
  end

  def render_error(message)
    render json: { errors: [message] }, status: :unprocessable_entity
  end
end
