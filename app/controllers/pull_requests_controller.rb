class PullRequestsController < ApplicationController
  before_action :set_local_repository
  before_action :set_pull_request, only: [:show, :update]

  def index
    default_base_branch = @local_repository.default_branch

    @pull_request = PullRequest.new(
      base_branch: default_base_branch,
      source_branch: default_source_branch(default_base_branch)
    )
    @pull_requests = @local_repository.pull_requests.order(created_at: :desc)
    @branches = @local_repository.branches
  end

  def create
    @pull_request = @local_repository.pull_requests.new(pull_request_params)

    if @pull_request.save
      redirect_to repository_pull_request_path(@local_repository, @pull_request)
    else
      @pull_requests = @local_repository.pull_requests.order(created_at: :desc)
      @branches = @local_repository.branches
      render :index, status: :unprocessable_entity
    end
  end

  def show
    load_pull_request_data
  end

  def update
    if @pull_request.update(pull_request_update_params)
      redirect_to repository_pull_request_path(@local_repository, @pull_request)
    else
      load_pull_request_data
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_local_repository
    @local_repository = LocalRepository.find(params[:repository_id])
  end

  def set_pull_request
    @pull_request = @local_repository.pull_requests.find(params[:id])
  end

  def pull_request_params
    params.require(:pull_request).permit(:source_branch, :base_branch, :description)
  end

  def pull_request_update_params
    params.require(:pull_request).permit(:base_branch, :description)
  end

  def default_source_branch(default_base_branch)
    return @local_repository.current_branch if @local_repository.current_branch != default_base_branch

    @local_repository.branches.map(&:name).find { |branch_name| branch_name != default_base_branch }
  end

  def load_pull_request_data
    @comparison = @pull_request.comparison
    @branches = @local_repository.branches
  end
end
