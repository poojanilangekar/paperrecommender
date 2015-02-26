class AddAttachmentUserdocToUsers < ActiveRecord::Migration
  def self.up
    change_table :users do |t|
      t.attachment :userdoc
    end
  end

  def self.down
    remove_attachment :users, :userdoc
  end
end
