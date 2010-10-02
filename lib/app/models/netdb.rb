class Netdb < ActiveRecord::Base
  belongs_to :vendor
  belongs_to :servertype
  has_many   :subnets, :foreign_key => "dhcp_id"

  validates_uniqueness_of :name
  validates_presence_of   :vendor_id, :servertype_id
  validates_associated    :vendor, :servertype
  validates_format_of     :address, :with => /(\S+\.){3}\S/

end
