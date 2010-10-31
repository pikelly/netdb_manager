module NetsvcManager
  mattr_accessor :dhcp_servers, :dhcp, :user_data
  
  module ActionControllerExtensions
    def self.included(base) #:nodoc:
      require 'resolv'
      require 'ipaddr'

      base.send :include, InstanceMethods
      base.class_eval do
        alias_method_chain :process, :netsvc_support
      end
    end
    
    module InstanceMethods
      def process_with_netsvc_support *args
        require_dependency 'netsvc_manager/host_ext'
        require_dependency 'netsvc_manager/user_ext'
        require_dependency 'netsvc_manager/subnet_ext'
        require_dependency 'netsvc_manager/domain_ext'
        require_dependency 'netsvc_manager/application_controller_ext'
        require_dependency 'netsvc_manager/hosts_controller_ext'
        process_without_netsvc_support *args
      end
    end
  end
end
ActionController::Base.send :include, NetsvcManager::ActionControllerExtensions
