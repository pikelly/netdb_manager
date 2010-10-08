module NetdbManager
  module HostExtensions
    def self.included(base)
      # This implementation requires memcache
      if [Rails.configuration.cache_store].flatten[0] == :mem_cache_store
        require_dependency 'implementation/lib/dhcp'
        #require_dependency 'iscdhcp'
        require_dependency 'ipaddr'
        include DHCP
      else
        message = "*********************************************************************\n" +
                  "DHCP and DNS management require that you install the memcache service\n" +
                  "and that you add this line to environment.db                         \n" +
                  "config.cache_store = :mem_cache_store                                \n" +
                  "and edit config.initializers/session_store to set = :mem_cache_store \n" +
                  "*********************************************************************\n"
        RAILS_DEFAULT_LOGGER.warn message
        puts message
        exit
      end

      base.extend  ClassMethods
      base.send :include, InstanceMethods
      base.class_eval do
        before_validation :load_netdb_caches
        after_validation  :check_dns
        after_save        :transactional_update, :save_netdb_caches
      end
      true
    end

    module InstanceMethods
      def check_dns
        
      end

      def save_netdb_caches
        
      end

      def delDHCP dhcpServer
        status = log_status("Delete a DHCP reservation for #{name}/#{ip}", dhcpServer){
          dhcpServer.delReservation self
        }
        return status unless sp_valid?
        log_status("Delete a DHCP reservation for #{sp_name}/#{sp_ip}", dhcpServer){
          dhcpServer.delReservation self, true
        }
      end
      # Updates the DHCP scope to add a reservation for this host
      # [+dhcpServer+]  : A DHCPServer object
      # +returns+       : Boolean true on success
      def setDHCP dhcpServer
        status = log_status("Add a DHCP reservation for #{name}/#{ip}", dhcpServer){
          dhcpServer.setReservation self
        }
        return status unless sp_valid?
        log_status("Add a DHCP reservation for #{sp_name}/#{sp_ip}", dhcpServer){
          dhcpServer.setReservation self, true
        }
      end
      
      def log_status message, server, &block
        if server
          logger.info "#{message}"
          unless result = yield(block)
            first, rest = message.match(/(\w*)(.*)/)[1,2]
            message = "Failed to " + first.downcase + rest + ": #{server.message}"
            errors.add_to_base server.message
            logger.error message
          end
          result
        else
          errors.add_to_base("Access denied")
          false
        end
      end
  
      def transactional_update
        puts "performing transactional update"
        Rails.logger.debug "performing transactional update"
        begin
          save_network_data
          true
        rescue
          errors.add_to_base "Failed to update the network databases"
          raise
          false
        end
      end
    end
  
    module ClassMethods
    end
  end
end

Host.send :include, NetdbManager::HostExtensions
