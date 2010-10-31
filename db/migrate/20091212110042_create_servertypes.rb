class CreateServertypes < ActiveRecord::Migration
  def self.up
    create_table :servertypes do |t|
      t.string :name, :limit =>  16, :null => false

      t.timestamps
    end
    Servertype.create :name => "DHCP"
    Servertype.create :name => "DNS"
    Servertype.create :name => "TFTP"
  end

  def self.down
    drop_table :servertypes
  end
end
