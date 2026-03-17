class AddStatusAndGithubUrlToPullRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :pull_requests, :status, :string, default: "open", null: false
    add_column :pull_requests, :github_pr_url, :string

    remove_index :pull_requests, name: "index_pull_requests_on_repository_and_source_branch"
    add_index :pull_requests, [:local_repository_id, :source_branch],
      unique: true,
      where: "status = 'open'",
      name: "index_pull_requests_on_repo_and_branch_when_open"
  end
end
