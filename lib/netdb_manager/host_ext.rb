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
        before_save :check_dns
        after_save  :update_netdbs
      end
      true
    end

    module InstanceMethods
      def check_dns
        continue = true
        @resolver = Resolv::DNS.new :search => domain.name, :nameserver => domain.dns.address
        if (@resolver.getaddress(name) rescue false)
          errors.add_to_base "#{name} is already in use"
          continue = false
        end
        if (@resolver.getname(ip) rescue false)
          errors.add_to_base "#{ip} is already in use"
          continue = false
        end
        continue
      end

      def save_netdb_caches
        
      end

      def getDHCP
        log_transaction("Query a DHCP reservation for #{name}/#{ip}", @dhcp){|dhcp|
          dhcp.get subnet.number, mac
        }
      end

      def delDHCP
        status = log_transaction("Delete a DHCP reservation for #{name}/#{ip}", @dhcp){|dhcp|
          dhcp.delete subnet.number, mac
        }
        return status unless sp_valid?
        log_transaction("Delete a DHCP reservation for #{sp_name}/#{sp_ip}"){|dhcp|
          dhcp.delete subnet.number, mac
        }
      end
      # Updates the DHCP scope to add a reservation for this host
      # +returns+ : Boolean true on success
      def setDHCP
        status = log_transaction("Add a DHCP reservation for #{name}/#{ip}", @dhcp){|dhcp|
          #nextserver needs to be an ip
          #resolver = Resolv::DNS.new :search => domain.name, :nameserver => domain.dns.address
          begin
            puppet = @resolver.getaddress(puppetmaster =~ /\./ ? puppetmaster : "#{puppetmaster}.#{domain.name}").to_s
          rescue Exception => e
            @dhcp.error = e.message =~/no information for puppet/ ? "Unable to find the address of the puppetmaster in #{domain}" : e.message
            return false
          end
          dhcp.set subnet.number, mac,  :name => name, :filename => media.bootfile, :ip => ip, :nextserver => puppet 
        }
        return status unless sp_valid?
        log_transaction("Add a DHCP reservation for #{sp_name}/#{sp_ip}", @dhcp){|dhcp|
          dhcp.set sp_subnet.number, sp_mac, :name => sp_name, :ip => sp_ip
        }
      end

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
  
      def update_netdbs
        return true if RAILS_ENV == "test"
        proxy_address = "http://#{subnet.dhcp.address}:4567"
        @dhcp = ProxyAPI::DHCP.new(:url => proxy_address)
        @dns  = ProxyAPI::DNS.new(:url => proxy_address)

        Rails.logger.debug "Performing transactional update"
        begin
          # We have just tested the validity of the DNS operation in check_dns, so if the operation fails it is not due to a conflict
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
          errors.add_to_base "Failed to update the network databases: " + e.message
          raise ActiveRecord::Rollback
          false
        end
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
