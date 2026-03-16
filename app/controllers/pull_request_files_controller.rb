class PullRequestFilesController < ApplicationController
  include RepositoryScoped

  before_action :set_pull_request

  def index
    load_review_data
    @query = params[:q].to_s.strip
    @layout = diff_preference(:layout) == "unified" ? :unified : :split
    @compact_line_height = diff_preference(:compact) != "0"
    @show_file_tree = diff_preference(:tree) != "0"
    @files = filtered_files(@comparison.files, @query)
  end

  private

  def set_pull_request
    @pull_request = @local_repository.pull_requests.find(params[:id])
  end

  def load_review_data
    @comparison = @pull_request.comparison
  end

  def filtered_files(files, query)
    return files if query.blank?

    files.select { |file| file.path.downcase.include?(query.downcase) }
  end
end
