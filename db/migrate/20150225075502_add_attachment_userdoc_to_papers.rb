class AddAttachmentUserdocToPapers < ActiveRecord::Migration
  def self.up
    change_table :papers do |t|
      t.attachment :userdoc
    end
  end

  def self.down
    remove_attachment :papers, :userdoc
  end
end
