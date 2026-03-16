module RepositoryScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_local_repository
  end

  private

  def set_local_repository
    @local_repository = LocalRepository.find_by!(name: params[:repository_name])
  end
end
