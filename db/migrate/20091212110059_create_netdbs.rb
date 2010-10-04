class CreateNetdbs < ActiveRecord::Migration
  def self.up
    create_table :netdbs do |t|
      t.string  :name,            :limit => 32, :null => false
      t.string  :address,         :limit => 32, :null => false
      t.integer :servertype_id,                 :null => false
      t.integer :vendor_id,                     :null => false

      t.timestamps
    end
    add_column :subnets, :dhcp_id, :integer
    if SETTINGS[:unattended].nil? or SETTINGS[:unattended]
      puts "**********************************************************************"
      puts "**********************************************************************"
      puts "**********************************************************************"
      puts "**********************************************************************"
      puts
      puts "Your installation requires a manual step for this upgrade"
      puts "Your hosts need to be assigned to a subnet"      
      puts "Please create your subnets in the settings/subnet page and then run"      
      puts "rake subnets:assign"
      puts "You may repeat this task until it reports all hosts have been assigned"
      puts
      puts "**********************************************************************"
      puts "**********************************************************************"
      puts "**********************************************************************"
      puts "**********************************************************************"
    end
  end

  def self.down
    drop_table    :netdbs
    remove_column :subnets, :dhcp_id
  end
end
