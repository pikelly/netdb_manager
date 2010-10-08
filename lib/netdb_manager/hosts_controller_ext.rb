module NetdbManager
  module HostsControllerExtensions
    def self.included(base) #:nodoc:
      base.send :include, InstanceMethods
      base.class_eval do
        before_filter :load_netdb_caches
      end

    end
    
    module InstanceMethods
      def subnet_selected
        dhcp = Subnet.find(params[:subnet_id]).dhcp
        
        DHCP.cache_server @dhcp_servers, @dhcp, @user_cache, dhcp
      end
    end
  end
end
HostsController.send :include, NetdbManager::HostsControllerExtensions
