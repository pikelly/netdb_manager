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
        @dhcp_servers = Rails.cache.fetch("dhcp_servers", :expires_in => NET_TTL){[]}.dup
        raise RuntimeException, "Unable to create DHCP memcache storage" unless @dhcp_servers

        # Fetch the memcached servers
        @dhcp = {}
        for server in @dhcp_servers
          @dhcp[server] = Rails.cache.fetch(server, :expires_in => NET_TTL){{}}.dup
          raise RuntimeError, "Unable to retrieve server data for #{server}" if @dhcp[server].size == 0
        end

        # Fetch the user data mecache. This holds per-user data dependant on the server implementation
        @user_cache = Rails.cache.fetch("user_cache", :expires_in => NET_TTL){{}}.dup
        raise RuntimeError, "Unable to create user cache storage" unless @user_cache

        # The DHCP instance needs access to the session as some of its DHCPServer implementations need to know about the user
        #per_user_data = @user_cache[@user.login]
        #@dhcp.personalise(per_user_data)
        true
      end

      def save_network_data
        return true if RAILS_ENV == "test"
        if @dhcp
          dhcpServer = @dhcp.serverFor subnet.number
          if new_record?
            setDHCP dhcpServer
          end
        else
          true # No netdb management unless we use memcache
        end
      end
    end
  end
end
ApplicationController.send :include, NetdbManager::ApplicationControllerExtensions
