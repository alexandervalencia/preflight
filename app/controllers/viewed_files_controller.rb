class ViewedFilesController < ApplicationController
  def create
    pull_request = PullRequest.find(params[:pull_request_id])
    viewed_file = pull_request.viewed_files.find_or_initialize_by(path: params[:path])

    mark_viewed = params[:viewed].nil? || ActiveModel::Type::Boolean.new.cast(params[:viewed])

    if mark_viewed
      viewed_file.update!(last_viewed_commit_sha: pull_request.head_sha)
    else
      viewed_file.destroy! if viewed_file.persisted?
    end

    redirect_to params[:redirect_to].presence || repository_pull_request_files_path(pull_request.local_repository, pull_request)
  end
end
