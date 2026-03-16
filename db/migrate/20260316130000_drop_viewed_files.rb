class DropViewedFiles < ActiveRecord::Migration[8.0]
  def change
    drop_table :viewed_files
  end
end
