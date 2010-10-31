module NetsvcManager
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
        attr_accessor :dns, :dhcp
        before_create :initialize_proxies, :check_netsvcs
        after_create  :create_netsvcs, :initialize_tftp
        after_update  :initialize_proxies, :update_netsvcs
        after_destroy :initialize_proxies, :destroy_netsvcs
      end
      true
    end

    module InstanceMethods
      # Ensure that the tftp bootfiles are available on the proxy host
      def initialize_tftp
        
      end
      # Checks whether DNS or DHCP entries already exist
      # Returns: Boolean true if no entries exists
      def check_netsvcs
        continue = true
        if (address = @resolver.getaddress(name) rescue false)
          errors.add_to_base "#{name} is already in DNS with an address of #{address}"
          continue = false
        end
        if (hostname = @resolver.getname(ip) rescue false)
          errors.add_to_base "#{ip} is already in the DNS with a name of #{hostname}"
          continue = false
        end
        if (entry = @dhcp.get subnet.number, mac) and @dhcp.error.empty?
          errors.add_to_base "#{subnet}/#{mac} is already managed by DHCP and configures #{entry["title"]}"
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
        @dhcp     = ProxyAPI::DHCP.new(:url => proxy_address)
        @dns      = ProxyAPI::DNS.new(:url => proxy_address)
        @resolver = Resolv::DNS.new :search => domain.name, :nameserver => domain.dns.address
      end

      def destroy_netsvcs
        return true if RAILS_ENV == "test"

        # We do not care about entries not being present when we delete them but comms errors, etc, must be reported
        if delDHCP or @dhcp.error =~ /Record/
          unless delDNS
            if @dns.error !~ /DNS delete failed/
              # Rollback the DHCP operation, if you can :-)
              setDHCP
              raise  @dns.error
            end
          end
        else
          raise  @dhcp.error
        end
        true
      rescue  => e
        errors.add_to_base "Failed to delete the network database entries: " + e.message
        raise ActiveRecord::Rollback
        false
      end

      def create_netsvcs
        return true if RAILS_ENV == "test"

        # We have just tested the validity of the DNS operation in check_netsvcs, so if the operation fails it is not due to a conflict
        # Therefore the operation failed because the write failed and therefore we do not need to rollback the DNS operation
        if setDNS
          unless setDHCP
            raise  @dhcp.error
          end
        else
          raise  @dns.error
        end
        true
      rescue => e
        errors.add_to_base "Failed to create the network database entries: " + e.message
        raise ActiveRecord::Rollback
        false
      end

      def update_netsvcs
        old = clone
        for key in (changed_attributes.keys - ["updated_at"])
          old.send "#{key}=", changed_attributes[key]
        end
        new = self

        #DHCP
        if old.subnet.dhcp.address != new.subnet.dhcp.address
          # we must create new proxy objects to talk to the old server
          old.initialize_proxies
          # We have changed server so delete on the old and recreate on the new
          raise  @dhcp.error unless old.delDHCP
          raise  @dhcp.error unless new.setDHCP
        else
          # We can reuse the proxy objects from the new host object
          old.dhcp, old.dns = new.dhcp, new.dns
          if changed_attributes.keys.grep /ip|mac|name|puppetmaster/
          raise  @dhcp.error unless old.delDHCP
          raise  @dhcp.error unless new.setDHCP
          end
        end

        # DNS
        # If the name or IP of the host have changed then remove entries and then create new ones
        if changed_attributes["ip"] or changed_attributes["name"]
          raise  @dns.error unless old.delDNS
          raise  @dns.error unless new.setDNS
        end
        true
      rescue => e
        errors.add_to_base "Failed to update the network database entries: " + e.message
        raise ActiveRecord::Rollback
        false
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

Host.send :include, NetsvcManager::HostExtensions
