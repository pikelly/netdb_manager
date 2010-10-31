class CreateVendors < ActiveRecord::Migration
  def self.up
    create_table :vendors do |t|
      t.string :name, :limit => 32, :null => false

      t.timestamps
    end
    Vendor.create :name => "Microsoft"
    Vendor.create :name => "ISC"
    Vendor.create :name => "Generic"
  end

  def self.down
    drop_table :vendors
  end
end
