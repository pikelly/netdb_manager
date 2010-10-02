# A generic module for dhcp queries and commands
# This is accessible on two levels:
#   A top-level hash based class which models all the subnets within the database
#   A second-level hash based class which represents a single DHCP server
# The second level class is vendor specific Currently we support Microsoft Servers
# via a web based gateway to the netsh.exe program and the InfoBlox DHCP server, which 
# is accessed directly
# The DHCP entries are cached in a Memcache store and are share among all users of the
# system
module DHCP
  # There has been a problem with the gateway transport or the data
  # we received does not make sense
  class DHCPError < RuntimeError;  end

  # This class models the DHCP subnets within the organisation
  # After initialisation 
  # dhcp = DHCP::Server.new(per_user_data_hash)
  # individual subnets can be referenced by
  # dhcp["172.29.216.0"]
  # and data is available via
  # mac = dhcp["172.29.216.0"]["172.29.216.12"]
  # A particular server can be found by
  # dhcp.serverFor["172.29.216.0"]
  class Dhcp < Hash
    attr_reader   :user
    attr_accessor :denied

    def to_s
      "[" + self.keys.join(",") + "]"
    end
    
    def logger; RAILS_DEFAULT_LOGGER; end
    
    # Set the per_user_data in this DHCP instance and in all DHCPServer instances
    # [+per_user_data+] : Hash located in the user's session
    def personalise per_user_data
      for server in @servers.values
        server.personalise per_user_data
      end
      # Extract the DHCP object's per_user_data
      # This is a list of server addresses that have denied us access or are unavailable
      # Some dhcp server implementations may grant or deny access based on the user
      @denied = per_user_data[:denied] ||= []
      @user   = per_user_data[:user]
    end
    
    # Populate my hash with {subnet_number => nil, subnet_number => nil, . . .}
    # These hashes will be filled in when the subnet is first accessed
    # [+per_user_data+] : Hash located in the user's session 
    def initialize(per_user_data)
      super()

      @servers = {}

      personalise per_user_data

      @initialized = false
      for subnet in Subnet.all.map(&:number)
        self[subnet] = nil
      end
      @initialized  = true
      flush
    end
      
    # A reference to a scope will instantiate the relevant DHCP server type and
    # link the server's scopes into this object
    #[+scope+] : String representation of the scope's IP address
    def [](scope)
      sn = Subnet.find_by_number(scope)
      dhcpServerAddress = sn.dhcp.address
      if self.has_key? scope and not @denied.include?(dhcpServerAddress) and @initialized and
            (self.fetch(scope).nil? or self.fetch(scope).size == 0)
        if @servers[dhcpServerAddress].nil?
          gateway           = sn.domain.gateway # This will be nil if using InfoBlox
          vendor            = sn.dhcp.vendor.name
          logger.debug "Cache miss for scope #{scope}"
          begin
            @servers[dhcpServerAddress] = eval("#{vendor}DHCPServer").new(dhcpServerAddress, self, gateway)
          rescue NameError
            raise "Failed to load DHCP vendor library. Class #{vendor}DHCPServer unavailable"
          end
          logger.debug "Loaded #{vendor} server #{dhcpServerAddress}"
        end
        server = @servers[dhcpServerAddress]
        # Do a cache probe to trigger a scope read
        server[scope]["0.0.0.0"]
        self[scope] = server[scope]
        flush
      end
      super # Finally call the Hash[] method to return the data that we have obtained 
    end

    # This method returns the dhcp server that manages this subnet It also loads the server's scopes whilst
    # it does this and therefore reports the user's permissions on that server
    # [+number+] : String representation of the desired subnet numer 
    def serverFor number
      # Trigger a cache probe to be sure that the server's data has been loaded
      self[number]
      sn = Subnet.find_by_number(number)
      @servers[sn.dhcp.address]
    end
  
    # Remove all cached ad uncached data for the subnet
    # [+subnet_number+] : String representation of the subnet's number
    def invalidate subnet_number
      logger.debug "Erasing DHCP data for #{subnet_number}"
      self[subnet_number] = nil
      server = serverFor subnet_number
      server[subnet_number] = nil
      flush
    end
  
    # Push our DHCP datastructure into the memcache for others to use
    def flush
      # Reserialize the DHCP data back into the cache
      # We have to use a dup or otherwise we are frozen.
      Rails.cache.write(:dhcp, self.dup, :expires_in => NET_TTL)
    end
  end # class Dhcp

  # This abstract class models a generic DHCP server
  # After initialisation
  # # dhcp = DHCPServer.new("172.29.216.40", parent DHCP object)
  # entries can be accessed by
  # mac  = dhcp["172.29.216"]["172.29.205.26"]
  class DHCPServer < Hash
    @@Option = {"hostname"                  => {"code" => 12, "vendor" => false, "type" => "string"},\
                "TFTP boot server"          => {"code" => 66, "vendor" => false, "type" => "string"},\
                "TFTP boot file"            => {"code" => 67, "vendor" => false, "type" => "string"},\
                "root server ip address"    => {"code" => 2,  "vendor" => true,  "type" => "ipaddress"},\
                "root path name"            => {"code" => 4,  "vendor" => true,  "type" => "string"},\
                "install server ip address" => {"code" => 10, "vendor" => true,  "type" => "ipaddress"},\
                "install server hostname"   => {"code" => 11, "vendor" => true,  "type" => "string"},\
                "install path"              => {"code" => 12, "vendor" => true,  "type" => "string"},\
                "sysid config file server"  => {"code" => 13, "vendor" => true,  "type" => "string"},\
                "jumpstart server"          => {"code" => 14, "vendor" => true,  "type" => "string"}\
               }
		
    @@debug  = false
    attr_reader :dhcpServerAddress, :dhcp, :message
  
    def logger; RAILS_DEFAULT_LOGGER; end
    def netdbType; "DHCP"; end
      
    def personalise per_user_data
      # Override this function in your vendor implemetion to retrieve per_user data
      # See DHCP#personalise
    end
    
    def denied?
      @dhcp.denied.include? @dhcpServerAddress
    end
  
    def to_s
      "[" + self.keys.join(",") + "]"
    end

    # A reference to a scopeIpAddress will populate our hash
    #[+ScopeIpAddress+] : String containing the scope IP address
    def [](scopeIpAddress)
      raise DHCPError.new("The subnet #{scopeIpAddress} is not managed by #{@dhcpServerAddress}") if not self.has_key? scopeIpAddress and not denied?
      if self.has_key? scopeIpAddress and self.fetch(scopeIpAddress).nil? and not denied?
        self[scopeIpAddress] = {}
        if loadScopeData scopeIpAddress, self.fetch(scopeIpAddress)
          @dhcp.flush
        else
          @dhcp.denied << @dhcpServerAddress
        end
      end
      super # Finally call the Hash[] method to return the data that we have obtained
    end

    # Connect to the named DHCP server and populate our hash keys with the scope that the machine servers
    # [+dhcpServerAdress+] : String containing the DHCP server's IP addresss
    # [+dhcp+]             : The parent Dhcp object 
    def initialize(dhcpServerAddress, dhcp)
      super()
  
      @dhcpServerAddress = dhcpServerAddress
      @dhcp = dhcp
      # This variable contains the last error detected in the library
      @message = ""
  
      scopes = loadScopes unless denied?
      if scopes
        scopes.each do |scope|
          self[scope] = nil
        end
      else
        @dhcp.denied << @dhcpServerAddress
      end
    end
    # Remove a DHCP reservation
    # [+host+] : Host object
    # [+sp+]   : Boolean which indicates whether we are dealing with the primary or service processor reservation
    def delReservation(host, sp = nil)
      scopeIpAddress = sp ? host.sp_subnet.number : host.subnet.number 
      ip             = sp ? host.sp_ip            : host.ip
      # It is not an error to remove an entry that does not exist. After all, the reservation has been removed. :-) 
      ((@message = "#{ip} is not registered in the DHCP") and return true) unless self[scopeIpAddress].has_key? ip
      
      if delRecordFor scopeIpAddress, ip
        # Reserialize the DHCP data back into the cache
        @dhcp.flush
        true
      else
        false
      end
    end
    
    # Create a DHCP reservation
    # [+host+] : Host object
    # [+sp+]   : Boolean which indicates whether we are dealing with the primary or service processor reservation
    def setReservation(host, sp = nil)
      scopeIpAddress = sp ? host.sp_subnet.number : host.subnet.number 
      ip             = sp ? host.sp_ip            : host.ip
      mac            = sp ? host.sp_mac           : host.mac
      name           = sp ? host.sp_name          : host.name
      (@message = "#{ip} already exists") and return false if self[scopeIpAddress].has_key? ip
      
      (@message = "Cannot determine the host's hardware or vendor class!") and return false \
        if (host.operatingsystem.name =~ /Solaris/ and host.architecture == "sparc") and (host.model.hclass.nil? or host.model.vclass.nil?) 

      # The puppetmaster value refers to the source of puppet manifests at runtime
      # All boot servers are fully qualified in DHCP to work around some strange PXE card issues
      if setRecordFor scopeIpAddress, ip, name, mac, host.media, host.model, host.architecture
        # Reserialize the DHCP data back into the cache
        @dhcp.flush
        true
      else
        false
      end
    end

    # Access a hosts DHCP reservation and replace the mac value with a hash which also includes additional DHCP options
    # This is alpha level code and is only implemented for MSDHCP servers
    # [+ip+] : String containing the IP Address
    def getDetails ip
      raise RuntimeError.new("Running the virtual DHCPServer.getDetails method! Please provide vendor specific code")
    end
    
    protected
    # A DHCP entry may be just a mac or a hash of attributes
    def MAC scopeIpAddress, ip
      record = self[scopeIpAddress][ip]
      mac    = record.is_a?(Hash) ? record[:mac] : record
      mac    = mac.gsub(/:/,"")
    end
    
    private
    def loadScopes
      raise RuntimeError.new("Running the virtual DHCPServer.loadScopes method! Please provide vendor specific code")
    end
    # Load a scope's reservation records
    # [+scopeIpAddress+] : String containing the scope's IP address
    # [+scope+]          : Hash into which we load the scop's data
    def loadScopeData scopeIpAddress, scope
      raise RuntimeError.new("Running the virtual DHCPServer.loadScopes method! Please provide vendor specific code")
    end
   # Add a DHCP entry
    # This method should be overriden in the subclass representing the type of DHCP server
    # [+scopeIpAddress+] : String containing the Scope's IP address
    # [+ip+]             : String containing the IP for the record to be removed
    # [+hostname+]       : String containing the host's name
    # [+mac+]            : String containing the host's MAC address
    # [+media+]          : Media object
    # [+model+]          : String containing the host's model. Required for sparc machines as this is encoded in MS DHCP servers
    # [+architecture+]   : String containing the host's architecture
    def setRecordFor(scopeIpAddress, ip, hostname, mac, media, model = nil, architecture = nil)
      raise RuntimeError.new("Running the virtual DHCPServer::setRecordFor method. Please provide vendor specific code")
    end
    # Delete the DHCP entry
    # This method should be overriden in the subclass representing the type of DHCP server
    # [+scopeIpAddress+] : String contaiing the Scope's IP address
    # [+ip+]             : String containing the IP address
    def delRecordFor(scopeIpAddress, ip)
      raise RuntimeError.new("Running the virtual DHCPServer::delRecordFor method! Please provide vendor specific code")
    end
  end # class DHCPServer

end # Module
