class PullRequestsController < ApplicationController
  before_action :set_pull_request, only: [:show, :update]

  def index
    default_base_branch = repository.default_branch

    @pull_request = PullRequest.new(
      base_branch: default_base_branch,
      source_branch: default_source_branch(default_base_branch)
    )
    @pull_requests = PullRequest.order(created_at: :desc)
    @branches = repository.branches
  end

  def create
    @pull_request = PullRequest.new(pull_request_params)

    if @pull_request.save
      redirect_to @pull_request
    else
      @pull_requests = PullRequest.order(created_at: :desc)
      @branches = repository.branches
      render :index, status: :unprocessable_entity
    end
  end

  def show
    @comparison = @pull_request.comparison
    @branches = repository.branches
    @comments_by_key = comments_by_key(@pull_request.inline_comments.where(commit_sha: nil))
    @viewed_files_by_path = @pull_request.viewed_files.index_by(&:path)
  end

  def update
    if @pull_request.update(pull_request_update_params)
      redirect_to @pull_request
    else
      @comparison = @pull_request.comparison
      @branches = repository.branches
      @comments_by_key = comments_by_key(@pull_request.inline_comments.where(commit_sha: nil))
      @viewed_files_by_path = @pull_request.viewed_files.index_by(&:path)
      render :show, status: :unprocessable_entity
    end
  end

  private

  def repository
    @repository ||= GitRepository.new(path: Rails.configuration.x.preflight.repository_path)
  end

  def set_pull_request
    @pull_request = PullRequest.find(params[:id])
  end

  def pull_request_params
    params.require(:pull_request).permit(:source_branch, :base_branch, :description)
  end

  def pull_request_update_params
    params.require(:pull_request).permit(:base_branch, :description)
  end

  def default_source_branch(default_base_branch)
    return repository.current_branch if repository.current_branch != default_base_branch

    repository.branches.map(&:name).find { |branch_name| branch_name != default_base_branch }
  end
end
