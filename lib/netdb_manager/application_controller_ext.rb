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

        # Fetch the user data mecache. This holds per-user data dependant on the server implementation
        NetdbManager.user_data = Rails.cache.fetch("user_data", :expires_in => NET_TTL){{}}.dup
        raise RuntimeError, "Unable to create user data cache storage" unless NetdbManager.user_data

        true
      end

    end
  end
end
ApplicationController.send :include, NetdbManager::ApplicationControllerExtensions
