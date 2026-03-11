class AddUniqueIndexToPullRequestsSourceBranch < ActiveRecord::Migration[8.1]
  class MigrationPullRequest < ApplicationRecord
    self.table_name = "pull_requests"

    has_many :inline_comments,
      class_name: "AddUniqueIndexToPullRequestsSourceBranch::MigrationInlineComment",
      foreign_key: :pull_request_id,
      dependent: :nullify
    has_many :viewed_files,
      class_name: "AddUniqueIndexToPullRequestsSourceBranch::MigrationViewedFile",
      foreign_key: :pull_request_id,
      dependent: :nullify
  end

  class MigrationInlineComment < ApplicationRecord
    self.table_name = "inline_comments"

    belongs_to :pull_request,
      class_name: "AddUniqueIndexToPullRequestsSourceBranch::MigrationPullRequest"
  end

  class MigrationViewedFile < ApplicationRecord
    self.table_name = "viewed_files"

    belongs_to :pull_request,
      class_name: "AddUniqueIndexToPullRequestsSourceBranch::MigrationPullRequest"
  end

  def up
    collapse_duplicate_pull_requests

    add_index :pull_requests, [:local_repository_id, :source_branch],
      unique: true,
      name: "index_pull_requests_on_repository_and_source_branch"
  end

  def down
    remove_index :pull_requests, name: "index_pull_requests_on_repository_and_source_branch"
  end

  private

  def collapse_duplicate_pull_requests
    duplicates = MigrationPullRequest.group(:local_repository_id, :source_branch)
      .having("COUNT(*) > 1")
      .count

    duplicates.each_key do |local_repository_id, source_branch|
      pull_requests = MigrationPullRequest.where(local_repository_id:, source_branch:)
        .order(:created_at, :id)
        .to_a
      canonical_pull_request = pull_requests.shift

      pull_requests.each do |duplicate_pull_request|
        duplicate_pull_request.inline_comments.update_all(pull_request_id: canonical_pull_request.id)
        duplicate_pull_request.viewed_files.find_each do |viewed_file|
          canonical_viewed_file = MigrationViewedFile.find_by(
            pull_request_id: canonical_pull_request.id,
            path: viewed_file.path
          )

          if canonical_viewed_file
            if canonical_viewed_file.updated_at <= viewed_file.updated_at
              canonical_viewed_file.update_columns(
                last_viewed_commit_sha: viewed_file.last_viewed_commit_sha,
                updated_at: viewed_file.updated_at
              )
            end
            viewed_file.destroy!
          else
            viewed_file.update!(pull_request_id: canonical_pull_request.id)
          end
        end

        duplicate_pull_request.destroy!
      end
    end
  end
end
