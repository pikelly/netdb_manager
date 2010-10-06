module NetdbManager
  module ActiveRecordExtensions
    def self.included(base) #:nodoc:
      base.send :include, InstanceMethods
      base.class_eval { alias_method_chain :before_save, :netdb_support }
    end
    
    module InstanceMethods
      def before_save_with_netdb_support
        if self.class.to_s == "Host"
          require_dependency 'netdb_manager/host_ext'
        elsif self.class.to_s == "User"
          require_dependency 'netdb_manager/user_ext'
        end
        before_save_without_netdb_support
      end
    end
  end
end
ActiveRecord::Callbacks.send :include, NetdbManager::ActiveRecordExtensions
