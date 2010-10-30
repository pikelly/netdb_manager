module NetdbManager
  module HostExtensions
    def self.included(base)
      # This implementation requires memcache
      if [Rails.configuration.cache_store].flatten[0] == :mem_cache_store
        require_dependency 'proxy_api'
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
        before_save   :initialize_proxies, :check_netdbs
        after_create  :create_netdbs
        after_update  :update_netdbs
        after_destroy :initialize_proxies, :destroy_netdbs
      end
      true
    end

    module InstanceMethods
      # Checks whether DNS or DHCP entries already exist
      # Returns: Boolean true if no entries exists
      def check_netdbs
        continue = true
        @resolver = Resolv::DNS.new :search => domain.name, :nameserver => domain.dns.address
        if (address = @resolver.getaddress(name) rescue false)
          errors.add_to_base "#{name} is already in DNS with an address of #{address}"
          continue = false
        end
        if (hostname = @resolver.getname(ip) rescue false)
          errors.add_to_base "#{ip} is already in the DNS with a name of #{hostname}"
          continue = false
        end
        if (entry = dhcp.get subnet.number, mac) and @dhcp.error.empty?
          errors.add_to_base "#{subnet}/#{mac} is already managed by DHCP and configures #{entry[:title]}"
          continue = false
        end
        continue
      end

      # Retrieves the DHCP entry for this host via a lookup on the MAC
      # Returns: Hash  Example {
      #   "omshell"   :true
      #   "mac"       :"22:33:44:55:66:11"
      #   "nextServer":"192.168.122.1"
      #   "title"     :"brsla804.brs.example.com"
      #   "filename"  :"pxelinux.0"
      #   "ip"        :"192.168.122.4"}
      def getDHCP
        log_transaction("Query a DHCP reservation for #{name}/#{ip}", @dhcp){|dhcp|
          dhcp.get subnet.number, mac
        }
      end

      # Deletes the DHCP entry for this host
      def delDHCP
        status = log_transaction("Delete a DHCP reservation for #{name}/#{ip}", @dhcp){|dhcp|
          dhcp.delete subnet.number, mac
        }
        return status unless sp_valid?
        log_transaction("Delete a DHCP reservation for #{sp_name}/#{sp_ip}"){|dhcp|
          dhcp.delete subnet.number, mac
        }
      end

      def fqdn_puppet
        @resolver.getaddress(puppetmaster =~ /\./ ? puppetmaster : "#{puppetmaster}.#{domain.name}").to_s
      rescue Exception => e
        @dhcp.error = e.message =~/no information for puppet/ ? "Unable to find the address of the puppetmaster in #{domain}" : e.message
        return false
      end

      # Updates the DHCP scope to add a reservation for this host
      # +returns+ : Boolean true on success
      def setDHCP
        status = log_transaction("Add a DHCP reservation for #{name}/#{ip}", @dhcp){|dhcp|
          #nextserver needs to be an ip
          return false unless puppet = fqdn_puppet

          dhcp.set subnet.number, mac,  :name => name, :filename => media.bootfile, :ip => ip, :nextserver => puppet 
        }
        return status unless sp_valid?
        log_transaction("Add a DHCP reservation for #{sp_name}/#{sp_ip}", @dhcp){|dhcp|
          dhcp.set sp_subnet.number, sp_mac, :name => sp_name, :ip => sp_ip
        }
      end

      # Returns: String containing the ip in the in-addr.arpa zone
      def to_arpa
        ip.split(/\./).reverse.join(".") + ".in-addr.arpa"
      end

      # Updates the DNS zones to add a host
      # +returns+ : Boolean true on success
      def setDNS
        log_transaction("Add the DNS records for #{name}/#{ip}", @dns){|dns|
          dns.set(name, :value => ip, :type => "A") &&
          dns.set(name, :value => to_arpa, :type => "PTR")
        }
      end

      # Removes the host from the forward and backward DNS zones
      # +returns+ : Boolean true on success
      def delDNS
        log_transaction("Delete the DNS records for #{name}/#{ip}", @dns){|dns|
          dns.delete(name) &&
          dns.delete(to_arpa)
        }
      end

      def log_transaction message, server
        logger.info "#{message}"
        unless result = yield(server)
          first, rest = message.match(/(\w*)(.*)/)[1,2]
          message = "Failed to " + first.downcase + rest + ": #{server.error}"
          errors.add_to_base server.error
          logger.error message
        end
        result
      end

      def initialize_proxies
        proxy_address = "http://#{subnet.dhcp.address}:4567"
        @dhcp = ProxyAPI::DHCP.new(:url => proxy_address)
        @dns  = ProxyAPI::DNS.new(:url => proxy_address)
      end

      def destroy_netdbs
        return true if RAILS_ENV == "test"

        initialize_proxies
        # We do not care about entries not being present when we delete them but comms errors, etc, must be reported
        begin
          if delDHCP
            unless delDNS
              if @dns.error !~ /Record/
                # Rollback the DHCP operation, if you can :-)
                setDHCP
                raise RuntimeError, @dns.error
              end
            end
          else
            if @dhcp.error !~ /Record/
              raise RuntimeError, @dhcp.error
            end
          end
        rescue  => e
          errors.add_to_base "Failed to delete the network database entries: " + e.message
          raise ActiveRecord::Rollback
          false
        end
      end

      def create_netdbs
        return true if RAILS_ENV == "test"

        initialize_proxies
        Rails.logger.debug "Performing transactional update"
        begin
          # We have just tested the validity of the DNS operation in check_netdbs, so if the operation fails it is not due to a conflict
          # Therefore the operation failed because the write failed and therefore we do not need to rollback the DNS operation
          if setDNS
            unless setDHCP
              raise RuntimeError, @dhcp.error
            end
          else
            raise RuntimeError, @dns.error
          end
          true
        rescue => e
          errors.add_to_base "Failed to create the network database entries: " + e.message
          raise ActiveRecord::Rollback
          false
        end
      end

      def update_netdbs
        
      end

      def sp_valid?
        !sp_name.empty? and !sp_ip.empty? and !sp_mac.empty?
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
