module NetdbManager
  module HostExtensions
    def self.included(base)
      # This implementation requires memcache
      if [Rails.configuration.cache_store].flatten[0] == :mem_cache_store
        require_dependency 'proxy_api'
        require_dependency 'ipaddr'
      else
        message = "*********************************************************************\n" +
                  "DHCP and DNS management require that you install the memcache service\n" +
                  "and that you add this line to environment.db                         \n" +
                  "config.cache_store = :mem_cache_store                                \n" +
                  "and edit config.initializers/session_store to set = :mem_cache_store \n" +
                  "!!!!Foreman will not operate until these tasks have been completed!!!\n" +
                  "*********************************************************************\n"
        RAILS_DEFAULT_LOGGER.warn message
        puts message
        exit
      end

      base.extend  ClassMethods
      base.send :include, InstanceMethods
      base.class_eval do
        after_validation  :check_dns
        after_save        :update_netdbs
      end
      true
    end

    module InstanceMethods
      def check_dns
        
      end

      def save_netdb_caches
        
      end

      def delDHCP dhcp_server
        status = log_transaction("Delete a DHCP reservation for #{name}/#{ip}", dhcp_server){
          dhcp_server.delReservation self
        }
        return status unless sp_valid?
        log_transaction("Delete a DHCP reservation for #{sp_name}/#{sp_ip}", dhcp_server){
          dhcp_server.delReservation self, true
        }
      end
      # Updates the DHCP scope to add a reservation for this host
      # [+dhcp_server+]  : A DHCPServer object
      # +returns+        : Boolean true on success
      def setDHCP dhcp
        status = log_transaction("Add a DHCP reservation for #{name}/#{ip}", dhcp_server){
          #nextserver needs to be an ip
          dhcp.set subnet.number, mac, :nextserver => resolver.getaddress(puppetmaster).to_s, :name => name, :filename => media.bootfile, :ip => ip
        }
        return status unless sp_valid?
        log_transaction("Add a DHCP reservation for #{sp_name}/#{sp_ip}", dhcp_server){
          dhcp.set sp_subnet.number, sp_mac, :name => sp_name, :ip => sp_ip
        }
      end
      
      def log_transaction message, server, &block
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
  
      def update_netdbs
        return true if RAILS_ENV == "test"

        Rails.logger.debug "performing transactional update"
        begin
          save_dhcp_data
          true
        rescue => e
          errors.add_to_base "Failed to update the network databases: " + e.message
          raise ActiveRecord::Rollback 
          false
        end
      end

      def save_dhcp_data
        dhcp = ProxyAPI::DHCP.new(:url => "http://#{subnet.dhcp.address}:4567") 
        if !dhcp.empty? and dhcp.subnets.include? subnet.number
          setDHCP dhcp_server
        else
          raise RuntimeError, "Unable to find the subnet in the cache"
        end
      end

      def validate
        # FIXME: host.errors.add :ip, "Subnet #{subnet} cannot contain #{ip}" unless self.subnet.contains? ip
      end
    end
  
    module ClassMethods
    end
  end
end

Host.send :include, NetdbManager::HostExtensions
