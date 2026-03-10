class LocalRepositoriesController < ApplicationController
  BrowseEntry = Data.define(:name, :path, :git_repository)

  def index
    @local_repository = LocalRepository.new
    @local_repositories = LocalRepository.order(:name)
  end

  def browse
    @directory = Pathname.new(params[:directory].presence || Dir.home).expand_path
    @parent_directory = @directory.root? ? nil : @directory.parent
    @entries = directory_entries(@directory)
  rescue Errno::ENOENT
    redirect_to root_path, alert: "That folder is no longer available."
  end

  def create
    @local_repository = LocalRepository.new(local_repository_params)

    if @local_repository.save
      redirect_to repository_pull_requests_path(@local_repository)
    else
      @local_repositories = LocalRepository.order(:name)
      render :index, status: :unprocessable_entity
    end
  end

  private

  def local_repository_params
    params.require(:local_repository).permit(:name, :path)
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
