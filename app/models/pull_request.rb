class PullRequest < ApplicationRecord
  belongs_to :local_repository

  validates :local_repository, presence: true
  validates :title, presence: true
  validates :source_branch, presence: true
  validates :base_branch, presence: true
  validates :source_branch, uniqueness: {
    scope: :local_repository_id,
    message: "already has an open local pull request"
  }
  validate :base_branch_differs_from_source_branch

  before_validation :assign_default_base_branch
  before_validation :assign_default_title

  def git_repository
    local_repository.git_repository
  end

  def comparison
    git_repository.compare(base: base_branch, head: source_branch)
  end

  def commits
    comparison.commits
  end

  def changed_files
    comparison.files
  end

  def head_sha
    git_repository.branch_head(source_branch)
  end

  private

  def assign_default_base_branch
    return if base_branch.present? || source_branch.blank? || local_repository.blank?

    self.base_branch = local_repository.default_branch
  end

  def assign_default_title
    return if title.present? || source_branch.blank?

    self.title = source_branch
  end

  def base_branch_differs_from_source_branch
    return if source_branch.blank? || base_branch.blank?
    return unless source_branch == base_branch

    errors.add(:base_branch, "must be different from the source branch")
  end
end
