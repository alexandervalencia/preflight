class LocalRepositoriesController < ApplicationController
  BrowseEntry = Data.define(:name, :path, :git_repository)

  def index
    @local_repositories = LocalRepository.order(:name)
    @pr_counts = PullRequest.where(local_repository_id: @local_repositories.select(:id))
      .group(:local_repository_id).count
  end

  def new
    @local_repository = LocalRepository.new
    load_new_page_data
  rescue Errno::ENOENT
    redirect_to new_repository_path, alert: "That folder is no longer available."
  end

  def browse
    redirect_to new_repository_path(directory: params[:directory])
  end

  def create
    @local_repository = LocalRepository.new(local_repository_params)

    if @local_repository.save
      redirect_to repository_pulls_path(@local_repository)
    else
      load_new_page_data
      render :new, status: :unprocessable_entity
    end
  end

  private

  def local_repository_params
    params.require(:local_repository).permit(:name, :path)
  end

  def load_new_page_data
    @discovered_repos = discover_repositories

    if params[:directory].present?
      @directory = Pathname.new(params[:directory]).expand_path
      @entries = directory_entries(@directory)
    end
  end

  def discover_repositories
    code_dir = Pathname.new(Dir.home).join("Code")
    return [] unless code_dir.directory?

    existing_paths = LocalRepository.pluck(:path).to_set

    code_dir.children.filter_map do |child|
      next unless child.directory?
      next if child.basename.to_s.start_with?(".")
      next unless GitRepository.valid_repository?(child.to_s)
      next if existing_paths.include?(child.to_s)

      BrowseEntry.new(name: child.basename.to_s, path: child.to_s, git_repository: true)
    end.sort_by(&:name)
  end

  def directory_entries(directory)
    directory.children.filter_map do |child|
      next unless child.directory?
      next if child.basename.to_s.start_with?(".")

      BrowseEntry.new(
        name: child.basename.to_s,
        path: child.to_s,
        git_repository: GitRepository.valid_repository?(child.to_s)
      )
    end.sort_by { |entry| [entry.git_repository ? 0 : 1, entry.name] }
  end
end
