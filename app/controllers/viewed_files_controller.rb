class ViewedFilesController < ApplicationController
  def create
    pull_request = PullRequest.find(params[:pull_request_id])
    viewed_file = pull_request.viewed_files.find_or_initialize_by(path: params[:path])
    viewed_file.update!(last_viewed_commit_sha: pull_request.head_sha)

    redirect_to pull_request_path(pull_request)
  end
end
