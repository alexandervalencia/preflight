class LocalRepository < ApplicationRecord
  has_many :pull_requests, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :path, presence: true, uniqueness: true
  validate :path_points_to_git_repository

  before_validation :assign_name

  def to_param
    name
  end

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
    resolve_name_collision if name.present?
  end

  def resolve_name_collision
    return unless new_record? || name_changed?
    return unless LocalRepository.where(name: name).where.not(id: id).exists?

    base_name = name
    (2..100).each do |counter|
      candidate = "#{base_name}-#{counter}"
      unless LocalRepository.where(name: candidate).where.not(id: id).exists?
        self.name = candidate
        return
      end
    end
  end

  def path_points_to_git_repository
    return if path.blank?
    return if GitRepository.valid_repository?(path)

    errors.add(:path, "must point to a local git repository")
  end
end
