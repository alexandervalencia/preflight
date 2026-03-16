class PullRequestCommitsController < ApplicationController
  before_action :set_local_repository
  before_action :set_pull_request

  def index
    @comparison = @pull_request.comparison
    @grouped_commits = @comparison.commits.group_by { |commit| commit.authored_at.to_date }
  end

  def show
    @comparison = @pull_request.comparison
    @commit = @pull_request.git_repository.commit(params[:id])
    @current_index = @comparison.commits.index { |commit| commit.sha == @commit.sha }
    @previous_commit = @current_index&.positive? ? @comparison.commits[@current_index - 1] : nil
    @next_commit = @current_index && @current_index < @comparison.commits.length - 1 ? @comparison.commits[@current_index + 1] : nil
    comments = @pull_request.inline_comments.where(commit_sha: @commit.sha)
    @comments_by_key = comments_by_key(comments)
    @comment_counts = comments.group(:path).count
    @query = params[:q].to_s.strip
    @layout = diff_preference(:layout) == "unified" ? :unified : :split
    @compact_line_height = diff_preference(:compact) != "0"
    @show_file_tree = diff_preference(:tree) != "0"
    @files = filtered_files(@commit.files, @query)
  end

  private

  def set_local_repository
    @local_repository = LocalRepository.find_by!(name: params[:repository_name])
  end

  def set_pull_request
    @pull_request = @local_repository.pull_requests.find(params[:pull_request_id])
  end

  def filtered_files(files, query)
    return files if query.blank?

    files.select { |file| file.path.downcase.include?(query.downcase) }
  end
end
