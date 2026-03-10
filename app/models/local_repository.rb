class LocalRepository < ApplicationRecord
  has_many :pull_requests, dependent: :destroy

  validates :name, presence: true
  validates :path, presence: true, uniqueness: true
  validate :path_points_to_git_repository

  before_validation :assign_name

  def git_repository
    @git_repository ||= GitRepository.new(path: path)
  end

  def branches
    git_repository.branches
  end

  def default_branch
    git_repository.default_branch
  end

  def current_branch
    git_repository.current_branch
  end

  private

  def assign_name
    self.name = File.basename(path) if name.blank? && path.present?
  end

  def path_points_to_git_repository
    return if path.blank?
    return if GitRepository.valid_repository?(path)

    errors.add(:path, "must point to a local git repository")
  end
end
