module NetdbManager
  module UserExtensions
    def self.included(base) #:nodoc:
      base.class_eval { alias_method_chain :try_to_login, :networking_support }
      base.extend  ClassMethods
      base.send :include, InstanceMethods
    end
    
    module InstanceMethods
    end
    
    module ClassMethods
      
      def try_to_login_with_networking_support(login, password)
        if user = try_to_login_without_network_support
          User.initialise_network_support
        end
        user
      end
  
      def initialise_network_cache
        return true unless @user
        return true if SETTINGS[:unattended] and SETTINGS[:unattended] == false
  
        @dhcp = Rails.cache.fetch(:dhcp, :expires_in => NET_TTL){
          DHCP::Dhcp.new(session)
        }.dup # For some reason the object is frozen in this implementation of the cache!
        raise RuntimeException, "Unable to create DHCP memcache storage" unless @dhcp
  
        # The DHCP instance needs access to the session as some of its DHCPServer implementations need to know about the user
        per_user_dhcp_data = session[:dhcp_data] ||= {:user => @user.login} 
        @dhcp.personalise(per_user_dhcp_data)
        true
      end
    end
  end
end
# And yes we need to put this in ActiveRecord and NOT User
User.send :include, NetdbManager::UserExtensions
