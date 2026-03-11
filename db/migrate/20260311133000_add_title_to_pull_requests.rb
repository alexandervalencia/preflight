class AddTitleToPullRequests < ActiveRecord::Migration[8.1]
  def up
    add_column :pull_requests, :title, :string

    execute <<~SQL
      UPDATE pull_requests
      SET title = source_branch
      WHERE title IS NULL OR title = ''
    SQL

    change_column_null :pull_requests, :title, false
  end

  def down
    remove_column :pull_requests, :title
  end
end
