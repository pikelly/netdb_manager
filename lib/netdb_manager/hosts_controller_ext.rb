module NetdbManager
  module HostsControllerExtensions
    def self.included(base) #:nodoc:
      base.send :include, InstanceMethods
      base.class_eval do
        before_filter :load_netdb_caches, :only => [:clone, :update, :create]
      end

    end
    
    module InstanceMethods
      def subnet_selected
        subnet = Subnet.find(params[:subnet_id])

        dhcp_server = DHCP.load_server subnet.dhcp
        dhcp_server.loadSubnetData DHCP::Server[subnet.number] if dhcp_server.find_subnet(subnet.number).size == 0
        NetdbManager.dhcp[subnet.dhcp.address] = dhcp_server
        head :ok
      end
    end
  end
end
HostsController.send :include, NetdbManager::HostsControllerExtensions
