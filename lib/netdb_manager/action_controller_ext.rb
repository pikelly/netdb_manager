module NetdbManager
  module ActionControllerExtensions
    def self.included(base) #:nodoc:
      base.send :include, InstanceMethods
      base.class_eval do
        alias_method_chain :process, :netdb_support
      end
    end
    
    module InstanceMethods
      def process_with_netdb_support *args
        require_dependency 'netdb_manager/host_ext'
        require_dependency 'netdb_manager/user_ext'
        require_dependency 'netdb_manager/application_controller_ext'
        process_without_netdb_support *args
      end
    end
  end
end
ActionController::Base.send :include, NetdbManager::ActionControllerExtensions