class AddUniqueIndexOnLocalRepositoryName < ActiveRecord::Migration[8.1]
  def change
    add_index :local_repositories, :name, unique: true
  end
end
