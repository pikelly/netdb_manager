module NetdbManager
  module SubnetExtensions
    def self.included(base) #:nodoc:
      base.extend  ClassMethods
      base.send :include, InstanceMethods
      base.class_eval do
        belongs_to :dhcp, :class_name => 'Netdb'
        validate_on_create :must_be_unique_per_site

      end
    end
    
    module InstanceMethods
      # Before we save a subnet ensure that we cannot find a subnet at our site with an identical name
      def must_be_unique_per_site
        if self.domain and self.domain.subnets
          unless self.domain.subnets.find_by_name(self.name).nil?
            errors.add_to_base "The name #{self.name} is already in use at #{self.domain.fullname}"
          end
        end
      end
  
    end
    
    module ClassMethods
      
    end
  end
end
Subnet.send :include, NetdbManager::SubnetExtensions
