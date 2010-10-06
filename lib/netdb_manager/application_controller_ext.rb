module NetdbManager
  module ApplicationControllerExtensions
    NET_TTL = 7200

    def self.included(base) #:nodoc:
      base.send :include, InstanceMethods
      base.class_eval do
        before_filter :initialise_caches
      end
    end
    
    module InstanceMethods
      def initialise_caches
        return true unless @user
        return true if SETTINGS[:unattended] and SETTINGS[:unattended] == false
  
        @dhcp = Rails.cache.fetch(:dhcp, :expires_in => NET_TTL){
          DHCP::Dhcp.new(session)
        }.dup # For some reason the object is frozen in this implementation of the cache!
        raise RuntimeException, "Unable to create DHCP memcache storage" unless @dhcp
  
        @user_cache = Rails.cache.fetch("user_cache", :expires_in => NET_TTL){
          {}
        }.dup # For some reason the object is frozen in this implementation of the cache!
        raise RuntimeException, "Unable to create password cache storage" unless @pass

        # The DHCP instance needs access to the session as some of its DHCPServer implementations need to know about the user
        per_user_data = @user_cache[login] 
        @dhcp.personalise(per_user_data)
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
ApplicaitonController::Base.send :include, NetdbManager::ApplicationControllerExtensions
