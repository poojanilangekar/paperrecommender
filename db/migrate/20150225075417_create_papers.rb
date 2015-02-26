class CreatePapers < ActiveRecord::Migration
  def change
    create_table :papers do |t|
      t.string :name
      t.text :keywords
      t.text :author
      t.text :references
      t.text :topics

      t.timestamps null: false
    end
  end
end
