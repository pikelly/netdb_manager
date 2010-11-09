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
        include ActionController::UrlWriter
        attr_accessor :dns, :dhcp
        before_create :initialize_proxies, :cache_tftp_files, :check_netdbs
        after_create  :create_netdbs, :create_tftp_config
        after_update  :initialize_proxies, :update_netdbs, :update_tftp_config
        after_destroy :initialize_proxies, :destroy_netdbs, :destroy_tftp_config
      end
      true
    end

    module InstanceMethods

      def create_tftp_config
        prefix        = operatingsystem.pxe_prefix(arch)
        kernel        = "#{prefix}-#{Redhat::PXEFILES[:kernel]}"
        initrd        = "#{prefix}-#{Redhat::PXEFILES[:initrd]}"
        kickstart_url = url_for :only_path => false, :controller => "unattended", :action => "kickstart", :host => "#{fqdn_puppet}#{Rails.env == "development" ? ":3000" : ""}"

        template = File.open("#{Rails.root}/vendor/plugins/netsvc_manager/app/views/unattended/pxe_kickstart_config.erb").read
        pxe_config = ERB.new(template).result(binding)

        success =  log_transaction("Create the PXE configuration for #{mac}", @tftp) do |tftp|
          tftp.set mac, :syslinux_config => pxe_config
        end
        raise @tftp.error unless success
        true
      rescue => e
        # We have just successfully created the netdbs at this point so removing them should probably work
        destroy_netdbs
        rollback "create the TFTP entry", e
      end

      def destroy_tftp_config
        success = log_transaction("Delete the PXE configuration for #{mac}", @tftp) do |tftp|
          tftp.delete mac
        end
        raise @tftp.error unless success
        true
      rescue => e
        # We have just successfully deleted the netdbs at this point so recreating them should probably work
        create_netdbs
        rollback "create the TFTP entry", e
      end

      def update_tftp_config
        status = destroy_tftp_config
        raise @tftp.error unless status && create_tftp_config
        true
      rescue => e
        # We have just successfully updated the netdbs at this point so reverting them should probably work
        # However we do not revert if this is just a setBuild operation
        update_netdbs true unless changed_attributes.keys ==  ["updated_at", "build"]
        rollback "update the TFTP entry", e
      end

      # Ensure that the tftp bootfiles are available on the proxy host
      def cache_tftp_files
        for bootfile_info in operatingsystem.pxe_files(media, architecture)
          for prefix, path in bootfile_info do
            return false unless \
            log_transaction("Download a bootfile from #{path} into #{prefix}", @tftp, true) do |tftp|
              tftp.fetch_boot_file :prefix => prefix.to_s, :path => path
            end
          end
        end
        true
      rescue => e
        errors.add_to_base "Failed to cache the TFTP files: " + e.message
        false # This triggers a rollback as this is a before filter
      end

      # Checks whether DNS or DHCP entries already exist
      # Returns: Boolean true if no entries exists
      def check_netdbs
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
        false
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

      # Adds the host to the forward and reverse DNS zones
      # +returns+ : Boolean true on success
      def setDNS
        log_transaction("Add the DNS records for #{name}/#{ip}", @dns){|dns|
          dns.set(name, :value => ip, :type => "A") &&
          dns.set(name, :value => to_arpa, :type => "PTR")
        }
      end

      # Removes the host from the forward and reverse DNS zones
      # +returns+ : Boolean true on success
      def delDNS
        log_transaction("Delete the DNS records for #{name}/#{ip}", @dns){|dns|
          dns.delete(name) &&
          dns.delete(to_arpa)
        }
      end

      # Runs the supplied block and, upon its failure, updates the log and adds errors to the host object
      # [+only_log_errors+] : Boolean indicating whether a message should be printed for a sucessful operation
      # For instance, we only log failure messages for the cache_tftp_files operation.
      def log_transaction message, server, only_log_errors = false
        logger.info "#{message}" unless only_log_errors
        unless result = yield(server)
          first, rest = message.match(/(\w*)(.*)/)[1,2]
          message = "Failed to " + first.downcase + rest + ": #{server.error}"
          errors.add_to_base server.error
          logger.error message
        end
        result
      end

      # Initializes the @dhcp,@dns, @tftp and @resolver objects
      def initialize_proxies
        @dhcp     = ProxyAPI::DHCP.new(:url => "http://#{subnet.dhcp.address}:4567")
        @dns      = ProxyAPI::DNS.new( :url => "http://#{domain.dns.address}:4567")
        @tftp     = ProxyAPI::TFTP.new(:url => "http://#{domain.tftp.address}:4567")
        @resolver = Resolv::DNS.new :search => domain.name, :nameserver => domain.dns.address
      rescue => e
        errors.add_to_base "Failed to initialize the network proxies: " + e.message
        false # Triggers a rollback as this is a before filter
      end

      def destroy_netdbs
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
        rollback "delete the network database entries", e
      end

      def create_netdbs
        # We have just tested the validity of the DNS operation in check_netsvcs, so if the operation fails it is not due to a conflict
        # Therefore the operation failed because the write failed and we do not need to rollback the DNS operation
        if setDNS
          unless setDHCP
            raise  @dhcp.error
          end
        else
          raise  @dns.error
        end
        true
      rescue => e
        rolback "create the network database entries", e
      end

      def update_netdbs revert=false
        old = clone
        for key in (changed_attributes.keys - ["updated_at"])
          old.send "#{key}=", changed_attributes[key]
        end
        new = self
        
        old, new = new, old if revert

        #DHCP
        if old.subnet.dhcp.address != new.subnet.dhcp.address
          # we must create another proxy object to talk to the old server
          revert ? new.initialize_proxies : old.initialize_proxies
          # We have changed server so delete on the old and recreate on the new
          raise  @dhcp.error unless old.delDHCP
          raise  @dhcp.error unless new.setDHCP
        else
          # We can reuse the proxy objects from the new host object
          old.dhcp, old.dns = new.dhcp, new.dns
          unless changed_attributes.keys.grep(/ip|mac|name|puppetmaster/).empty?
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
        rollback "update the network database entries", e
      end

      def sp_valid?
        !sp_name.empty? and !sp_ip.empty? and !sp_mac.empty?
      end

      def validate
        true
        # FIXME: host.errors.add :ip, "Subnet #{subnet} cannot contain #{ip}" unless self.subnet.contains? ip
      end

      private
      def rollback comment, exception
        errors.add_to_base "Failed to #{comment}: " + exception.message
        raise ActiveRecord::Rollback
      end
    end
  
    module ClassMethods
    end
  end
end

Host.send :include, NetsvcManager::HostExtensions
