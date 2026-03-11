class PullRequestFilesController < ApplicationController
  before_action :set_local_repository
  before_action :set_pull_request

  def index
    load_review_data
    @query = params[:q].to_s.strip
    @files = filtered_files(@comparison.files, @query)
  end

  private

  def set_local_repository
    @local_repository = LocalRepository.find(params[:repository_id])
  end

  def set_pull_request
    @pull_request = @local_repository.pull_requests.find(params[:id])
  end

  def load_review_data
    @comparison = @pull_request.comparison
    @comments_by_key = comments_by_key(@pull_request.inline_comments.where(commit_sha: nil))
    @viewed_files_by_path = @pull_request.viewed_files.index_by(&:path)
  end

  def filtered_files(files, query)
    return files if query.blank?

    files.select { |file| file.path.downcase.include?(query.downcase) }
  end
end
