class Paper < ActiveRecord::Base
 has_attached_file :userdoc  
 validates_attachment_content_type :userdoc, :content_type =>['application/pdf']
end
