class PullRequest < ApplicationRecord
  has_many :inline_comments, dependent: :destroy
  has_many :viewed_files, dependent: :destroy

  validates :source_branch, presence: true
  validates :base_branch, presence: true
  validate :base_branch_differs_from_source_branch

  before_validation :assign_default_base_branch

  def repository
    @repository ||= GitRepository.new(path: repository_path)
  end

  def repository_path
    Rails.configuration.x.preflight.repository_path
  end

  def comparison
    repository.compare(base: base_branch, head: source_branch)
  end

  def commits
    comparison.commits
  end

  def changed_files
    comparison.files
  end

  def head_sha
    repository.branch_head(source_branch)
  end

  private

  def assign_default_base_branch
    self.base_branch = repository.default_branch if base_branch.blank? && source_branch.present?
  end

  def base_branch_differs_from_source_branch
    return if source_branch.blank? || base_branch.blank?
    return unless source_branch == base_branch

    errors.add(:base_branch, "must be different from the source branch")
  end
end
