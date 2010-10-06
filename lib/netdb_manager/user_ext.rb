module NetdbManager
  module UserExtensions
    NET_TTL = 7200
    def self.included(base) #:nodoc:
      base.extend  ClassMethods
      base.send :include, InstanceMethods
      base.class_eval do
        class << self
          alias_method_chain :try_to_login, :netdb_support
        end
      end
    end
    
    module InstanceMethods
    end
    
    module ClassMethods
      
      def try_to_login_with_netdb_support(login, password)
        if user = self.try_to_login_without_netdb_support(login, password)
          User.capture_user_data user
        end
        user
      end
  
      def capture_user_data user
        if @user_cache
          @user_cache[user.login] = {:password => user.password, :rejected => {}}
          Rails.cache.write "user_cache", @user_cache, :expires_in => NET_TTL
        end
        true
      end
    end
  end
end
User.send :include, NetdbManager::UserExtensions
