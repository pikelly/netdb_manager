module NetdbManager
  module ApplicationControllerExtensions
    NET_TTL = 7200

    def self.included(base) #:nodoc:
      base.send :include, InstanceMethods
      base.class_eval do
        # Setting the filter chain here will not work as it is too late. Set it in each controller individually.
        #before_filter :load_netdb_caches
      end
      true
    end

    module InstanceMethods
      def load_netdb_caches
        raise RuntimeError "Unable to determine the user for this operation " unless @user
        return true if SETTINGS[:unattended] and SETTINGS[:unattended] == false

        # Fetch the list of server that are memcached
#        NetdbManager.dhcp_servers = Rails.cache.fetch("dhcp_servers", :expires_in => NET_TTL){[]}.dup
#        raise RuntimeException, "Unable to create DHCP memcache storage" unless NetdbManager.dhcp_servers

        # Fetch the memcached servers
        NetdbManager.dhcp = {}
        for server in NetdbManager.dhcp_servers
          NetdbManager.dhcp[server] = Rails.cache.fetch(server, :expires_in => NET_TTL){{}}.dup
          raise RuntimeError, "Unable to retrieve server data for #{server}" if NetdbManager.dhcp[server].size == 0
        end

        # Fetch the user data mecache. This holds per-user data dependant on the server implementation
        NetdbManager.user_data = Rails.cache.fetch("user_data", :expires_in => NET_TTL){{}}.dup
        raise RuntimeError, "Unable to create user data cache storage" unless NetdbManager.user_data

        # The DHCP instance needs access to the session as some of its DHCPServer implementations need to know about the user
        #per_user_data = @user_cache[@user.login]
        #@dhcp.personalise(per_user_data)
        true
      end

    end
  end
end
ApplicationController.send :include, NetdbManager::ApplicationControllerExtensions
