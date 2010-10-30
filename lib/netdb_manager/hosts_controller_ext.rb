module NetdbManager
  module HostsControllerExtensions
    def self.included(base) #:nodoc:
      base.send :include, InstanceMethods
      base.class_eval do
      end

    end
    
    module InstanceMethods
    end
  end
end
HostsController.send :include, NetdbManager::HostsControllerExtensions
