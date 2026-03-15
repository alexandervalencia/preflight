class PullRequestsController < ApplicationController
  before_action :set_local_repository
  before_action :set_pull_request, only: [:show, :update]

  def index
    @pull_requests = @local_repository.pull_requests.order(created_at: :desc)
  end

  def compare
    @pull_request = PullRequest.new(
      base_branch: selected_base_branch,
      source_branch: selected_source_branch
    )
    @branches = @local_repository.branches
    @existing_pull_request = existing_pull_request_for(@pull_request.source_branch)
    load_comparison if @pull_request.base_branch != @pull_request.source_branch
  end

  def create
    if (existing_pull_request = existing_pull_request_for(pull_request_params[:source_branch]))
      redirect_to repository_pull_path(@local_repository, existing_pull_request)
      return
    end

    @pull_request = @local_repository.pull_requests.new(pull_request_params)

    if @pull_request.save
      redirect_to repository_pull_path(@local_repository, @pull_request)
    else
      @branches = @local_repository.branches
      @existing_pull_request = existing_pull_request_for(@pull_request.source_branch)
      load_comparison if @pull_request.base_branch != @pull_request.source_branch
      render :compare, status: :unprocessable_entity
    end
  end

  def show
    load_pull_request_data
  end

  def update
    if @pull_request.update(pull_request_update_params)
      redirect_to repository_pull_path(@local_repository, @pull_request)
    else
      load_pull_request_data
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_local_repository
    @local_repository = LocalRepository.find_by!(name: params[:repository_name])
  end

  def set_pull_request
    @pull_request = @local_repository.pull_requests.find(params[:id])
  end

  def pull_request_params
    params.require(:pull_request).permit(:title, :source_branch, :base_branch, :description)
  end

  def pull_request_update_params
    params.require(:pull_request).permit(:title, :base_branch, :description)
  end

  def default_source_branch(default_base_branch)
    return @local_repository.current_branch if @local_repository.current_branch != default_base_branch

    @local_repository.branches.map(&:name).find { |branch_name| branch_name != default_base_branch }
  end

  def selected_base_branch
    params[:base_branch].presence || @local_repository.default_branch
  end

  def selected_source_branch
    params[:source_branch].presence || default_source_branch(selected_base_branch)
  end

  def existing_pull_request_for(source_branch)
    return if source_branch.blank?

    @local_repository.pull_requests.find_by(source_branch:)
  end

  def load_pull_request_data
    @comparison = @pull_request.comparison
    @branches = @local_repository.branches
  end

  def load_comparison
    @comparison = @local_repository.git_repository.compare(
      base: @pull_request.base_branch,
      head: @pull_request.source_branch
    )
    @commits = @comparison.commits
    @grouped_commits = @commits.group_by { |c| c.authored_at.to_date }
    @files = @comparison.files
  end
end
