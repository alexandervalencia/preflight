class PullRequestCommitsController < ApplicationController
  before_action :set_pull_request

  def show
    @comparison = @pull_request.comparison
    @commit = @pull_request.repository.commit(params[:id])
    @current_index = @comparison.commits.index { |commit| commit.sha == @commit.sha }
    @previous_commit = @current_index&.positive? ? @comparison.commits[@current_index - 1] : nil
    @next_commit = @current_index && @current_index < @comparison.commits.length - 1 ? @comparison.commits[@current_index + 1] : nil
    @comments_by_key = comments_by_key(@pull_request.inline_comments.where(commit_sha: @commit.sha))
  end

  private

  def set_pull_request
    @pull_request = PullRequest.find(params[:pull_request_id])
  end
end
