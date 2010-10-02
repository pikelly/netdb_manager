module NetdbManager
  def self.included(base)
    # This implementation requires memcache
    if [Rails.configuration.cache_store].flatten[0] == :mem_cache_store
      require 'dhcp'
      require 'iscdhcp'
      require 'ipaddr'
      include DHCP
    else
      if SETTINGS[:unattended].nil? or SETTINGS[:unattended]
        RAILS_DEFAULT_LOGGER.warn "*********************************************************************"
        RAILS_DEFAULT_LOGGER.warn "DHCP and DNS management require that you install the memcache service"
        RAILS_DEFAULT_LOGGER.warn "and that you add this line to environment.db"
        RAILS_DEFAULT_LOGGER.warn "config.cache_store = :mem_cache_store"
        RAILS_DEFAULT_LOGGER.warn "*********************************************************************"
      end
      @dhcp = nil
      return
    end

    base.extend  ClassMethods
    base.send :include, InstanceMethods
  end

  module InstanceMethods
    def save_network_data
      return true if RAILS_ENV == "test"
      if @dhcp
        dhcpServer = @dhcp.serverFor subnet.number
        if new_record?
          setDHCP dhcpServer
        end
      else
        true # No netdb management unless we use memcache
      end
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
      begin
        initialise_network_cache
        save_network_data
        true
      rescue => e
        errors.add_to_base "Failed to update the network databases"
        raise ActiveRecord::Rollback + e.message
        false
      end
    end
  end

  module ClassMethods
    def initialise_network_cache
      return true unless @user
      return true if SETTINGS[:unattended] and SETTINGS[:unattended] == false

      @dhcp = Rails.cache.fetch(:dhcp, :expires_in => NET_TTL){
        DHCP::Dhcp.new(session)
      }.dup # For some reason the object is frozen in this implementation of the cache!
      raise RuntimeException, "Unable to create DHCP memcache storage" unless @dhcp

      # The DHCP instance needs access to the session as some of its DHCPServer implementations need to know about the user
      per_user_dhcp_data = session[:dhcp_data] ||= {:user => @user.login} 
      @dhcp.personalise(per_user_dhcp_data)
      true
    end

    def reload_network_data
      Rails.cache.clear
      head :created
    end
  end
end

# And yes we need to put this in ActiveRecord and NOT Host
ActiveRecord::Base.send :include, NetdbManager
