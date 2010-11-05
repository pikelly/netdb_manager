class AddDnsColumn < ActiveRecord::Migration
  def self.up
    add_column :domains, :dns_id, :integer
    add_column :domains, :tftp_id, :integer
  end

  def self.down
    remove_column :domains, :tftp_id
    remove_column :domains, :dns_id
  end
end
