class ViewedFile < ApplicationRecord
  belongs_to :pull_request

  validates :path, presence: true
  validates :last_viewed_commit_sha, presence: true

  def current?(repository: pull_request.git_repository)
    !repository.file_changed?(from: last_viewed_commit_sha, to: pull_request.head_sha, path: path)
  end
end
