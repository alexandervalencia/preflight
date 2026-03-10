class CreatePullRequestRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :pull_requests do |t|
      t.string :source_branch, null: false
      t.string :base_branch, null: false
      t.text :description, null: false, default: ""

      t.timestamps
    end

    create_table :inline_comments do |t|
      t.references :pull_request, null: false, foreign_key: true
      t.string :commit_sha
      t.string :path, null: false
      t.string :side, null: false
      t.integer :line_number, null: false
      t.text :body, null: false

      t.timestamps
    end

    create_table :viewed_files do |t|
      t.references :pull_request, null: false, foreign_key: true
      t.string :path, null: false
      t.string :last_viewed_commit_sha, null: false

      t.timestamps
    end

    add_index :viewed_files, [:pull_request_id, :path], unique: true
  end
end
