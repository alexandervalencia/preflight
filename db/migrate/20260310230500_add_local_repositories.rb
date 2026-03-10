class AddLocalRepositories < ActiveRecord::Migration[8.1]
  class MigrationLocalRepository < ActiveRecord::Base
    self.table_name = "local_repositories"
  end

  class MigrationPullRequest < ActiveRecord::Base
    self.table_name = "pull_requests"
  end

  def up
    create_table :local_repositories do |t|
      t.string :name, null: false
      t.string :path, null: false

      t.timestamps
    end

    add_index :local_repositories, :path, unique: true

    add_reference :pull_requests, :local_repository, foreign_key: true

    default_repository = MigrationLocalRepository.create!(
      name: File.basename(Rails.root),
      path: Rails.root.to_s
    )

    MigrationPullRequest.update_all(local_repository_id: default_repository.id)
    change_column_null :pull_requests, :local_repository_id, false
  end

  def down
    remove_reference :pull_requests, :local_repository, foreign_key: true
    drop_table :local_repositories
  end
end
