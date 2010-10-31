module NetsvcManager
  module UserExtensions
    NET_TTL = 7200
    def self.included(base) #:nodoc:
      base.extend  ClassMethods
      base.send :include, InstanceMethods
      base.class_eval do
        class << self
          alias_method_chain :try_to_login, :netsvc_support
        end
      end
    end
    
    module InstanceMethods
    end
    
    module ClassMethods
      
      def try_to_login_with_netsvc_support(login, password)
        if user = self.try_to_login_without_netsvc_support(login, password)
          User.capture_user_data user
        end
        user
      end
  
      def capture_user_data user
        if @user_data
          @user_data[user.login] = {:password => user.password, :rejected => {}}
          Rails.cache.write "user_cache", @user_data, :expires_in => NET_TTL
        end
        true
      end
    end
  end
end
User.send :include, NetsvcManager::UserExtensions
