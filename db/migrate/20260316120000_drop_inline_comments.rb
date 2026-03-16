class DropInlineComments < ActiveRecord::Migration[8.0]
  def change
    drop_table :inline_comments
  end
end
