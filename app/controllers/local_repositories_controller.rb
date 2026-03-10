class LocalRepositoriesController < ApplicationController
  def index
    @local_repository = LocalRepository.new
    @local_repositories = LocalRepository.order(:name)
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
end
