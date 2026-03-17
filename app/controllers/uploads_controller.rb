class UploadsController < ApplicationController
  include RepositoryScoped

  skip_before_action :set_local_repository, only: :show
  skip_forgery_protection only: :create

  ALLOWED_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze
  MAX_SIZE = 10.megabytes

  def create
    @pull_request = @local_repository.pull_requests.find(params[:id])
    file = params[:file]

    unless file.is_a?(ActionDispatch::Http::UploadedFile)
      return render json: { error: "No file provided" }, status: :unprocessable_entity
    end

    unless ALLOWED_TYPES.include?(file.content_type)
      return render json: { error: "File type not allowed. Use PNG, JPG, GIF, or WebP." }, status: :unprocessable_entity
    end

    if file.size > MAX_SIZE
      return render json: { error: "File too large. Maximum 10MB." }, status: :unprocessable_entity
    end

    filename = sanitize_filename(file.original_filename)
    pr_dir = uploads_dir_for(@pull_request)
    FileUtils.mkdir_p(pr_dir)
    dest = File.join(pr_dir, filename)
    FileUtils.cp(file.tempfile.path, dest)

    url = preflight_upload_path(pull_request_id: @pull_request.id, filename:)
    markdown = "![#{filename}](#{url})"

    render json: { url:, markdown:, filename: }, status: :created
  end

  def show
    pull_request_id = params[:pull_request_id]
    filename = params[:filename]
    file_path = File.join(uploads_base_dir, pull_request_id.to_s, filename)

    if File.exist?(file_path)
      send_file file_path, disposition: :inline
    else
      head :not_found
    end
  end

  private

  def uploads_base_dir
    ENV.fetch("PREFLIGHT_UPLOADS_PATH") { File.expand_path("~/.preflight/uploads") }
  end

  def uploads_dir_for(pull_request)
    File.join(uploads_base_dir, pull_request.id.to_s)
  end

  def sanitize_filename(filename)
    filename.gsub(/[^\w.\-]/, "_")
  end
end
