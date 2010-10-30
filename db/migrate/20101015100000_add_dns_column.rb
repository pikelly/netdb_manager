class AddDnsColumn < ActiveRecord::Migration
  def self.up
    add_column :domains, :dns_id, :integer
  end

  def self.down
    remove_column :domains, :dns_id
  end
end
