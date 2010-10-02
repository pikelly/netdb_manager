# This class models a ISC DHCP server 
# After initialiasation, entries can be accessed by
# dhcp = ISCServer.new("172.29.216.40", dhcp)
# ip    = dhcp["172.29.216"]["000c291c34f2"]
class ISCDHCPServer < DHCP::DHCPServer

  # Delete the DHCP entry
  # This method is vendor specific and updates the DHCP server via the adaptor
  # [+scopeIpAddress+] : String containing the Scope's IP address
  # [+ip+]             : String containing the IP for the record to be removed
  def delRecordFor(scopeIpAddress, ip)
    record = self[scopeIpAddress][ip]
    mac    = record.is_a?(Hash) ? record[:mac] : record
    #mac    = mac.gsub(/:/,"")

    omcmd "connect"
    omcmd "set hardware-address = #{mac}"
    omcmd "open"
    omcmd "remove"
    omcmd "disconnect"
    
    Util.syslog "#{@dhcp.user} removed DHCP reservation for #{ip}/#{mac}"
    self[scopeIpAddress].delete ip
    true
  end
  protected

  # Add a DHCP entry
  # This method is vendor specific and updates the dhcp entry via the adaptor
  # [+scopeIpAddress+] : String containing the Scope's IP address
  # [+ip+]             : String containing the IP for the record to be removed
  # [+name+]           : String containing the host's name
  # [+mac+]            : String containing the host's MAC address
  # [+media+]          : Media object
  # [+model+]          : String containing the host's model  Required for sparc machines as this is encoded in MS DHCP servers
  # [+architecture+]   : Architecture object
  def setRecordFor(scopeIpAddress, ip, name, mac, media, model=nil, architecture = nil)
    (@message = "#{mac} already exists in scope #{scopeIpAddress}!" and return false) if self[scopeIpAddress].has_value? mac

    omcmd "connect"
    omcmd "set name = \"#{name}\""
    omcmd "set ip-address = #{ip}"
    omcmd "set hardware-address = #{mac}"
    omcmd "set hardware-type = 1"         # This is ethernet

    self[scopeIpAddress][ip] = mac

    unless media.bootserver.nil?  # We are done if this is a service processor reservation
      hexserv = Resolv.getaddress(media.bootserver).split(".").map{|i| "%02x" % i }.join(":")


      omcmd "set statements = \"filename = \\\"#{"kickstart/" + media.bootfile}\\\";\""
  
      if architecture.name == "sparc"
        #TODO: Add Sun vendor options
      end
    end  
    omcmd "create"
    omcmd "disconnect"
    Util.syslog "#{@dhcp.user} created DHCP reservation for #{name} @ #{ip}/#{mac}"
    true
  end
  # Connect to the named DHCP server and populate our hash keys with the scope that the machine servers
  # [+dhcpServerAdress+] : String containing the DHCP server's IP addresss
  # [+dhcp+]             : Dhcp object refering to parent
  def initialize(dhcpServerAddress, dhcp, option)
    # Connect to the named DHCP server and download its reservations
    @dhcpd_conf   = nil
    @dhcpd_leased = nil
    @netmask      = {}
    super(dhcpServerAddress, dhcp)
    # For now we make the assumption that this code runs on the dhcpd server
  end

  private
  def omcmd cmd, *args
    if cmd == "connect"
      @om = IO.popen("/usr/bin/omshell", "r+")
      server_addr = @dhcpServerAddress=~/^\d/ ? @dhcpServerAddress : Resolv.getaddress(@dhcpServerAddress) 
      @om.puts "server #{server_addr}"
      @om.puts "connect"
      @om.puts "new host"
    elsif
      cmd == "disconnect"
      @om.close_write
      status = @om.readlines
      @om.close
      @om = nil # we cannot serialize an IO obejct, even if closed.
      status=~/can't/
    else
      @om.puts cmd
    end
  end
  def download_configuration
    if @dhcpd_conf
      system "scp -B -q #{@dhcpServerAddress}:#{@dhcpd_conf} /tmp" if not FileTest.file? "/tmp/dhcpd.conf" or File.mtime("/tmp/dhcpd.conf") > Time.now - 5.minutes
    else
      if    system("scp -B -q #{@dhcpServerAddress}:/etc/dhcp3/dhcpd.conf /tmp")
        @dhcpd_conf = "/etc/dhcp3/dhcpd.conf"
      elsif system("scp -B -q #{@dhcpServerAddress}:/etc/dhcpd.conf /tmp")
        @dhcpd_conf = "/etc/dhcpd.conf"
      end
    end
    @message = "Unable to retrieve the DHCP configuration file from #{@dhcpServerAddress}" and return false unless FileTest.file? "/tmp/dhcpd.conf"
    if @dhcpd_leases    
      system "scp -B -q #{@dhcpServerAddress}:#{@dhcpd_leases} /tmp" if not FileTest.file? "/tmp/dhclient.leases" or File.mtime("/tmp/dhclient.leases") > Time.now - 5.minutes
    else
      if    system("scp -B -q #{@dhcpServerAddress}:/var/lib/dhcp3/dhcpd.leases /tmp")
        @dhcpd_leases = "/var/lib/dhcp3/dhcpd.leases"
      elsif system("scp -B -q #{@dhcpServerAddress}:/var/lib/dhcp/dhcpd.leases /tmp")
        @dhcpd_leases = "/var/lib/dhcp/dhcpd.leases"
      end
    end
    @@messsage = "Unable to retrieve the DHCP leases file from #{@dhcpServerAddress}" and return false unless FileTest.file? "/tmp/dhcpd.leases"
    true
  end
  # Enumerates the server's scopes
  # Returns a list of active scopes
  def loadScopes
    return false unless download_configuration
    entries = open("/tmp/dhcpd.conf"){|f|f.readlines}.delete_if{|l| not l=~/^\s*subnet/}.map{|l| l.match(/^\s*subnet\s+([\d\.]+)\s+netmask\s+([\d\.]+)/)[1,2]}
    scopes = []
    for subnet, netmask in entries
      @netmask[subnet] = netmask
      scopes << subnet
    end
    @message = "No scopes were found on #{@dnsServerAddress}" and return false if scopes.empty?
    scopes
  end
  # Load a scopes' reservation records
  # [+scopeIpAddress+] : String containing the scope's IP address
  # [+scope+]          : Hash to be populated by the load operation
  def loadScopeData scopeIpAddress, scope
    logger.debug "Loading scope: " + scopeIpAddress
    return false unless download_configuration
    # Populate the hash that represent the scope reservations
    # Skip the first few lines returned by the server and gateway code

    # Clear the hash as we maybe reloading the cache
    scope.clear

    # Extract the data
    conf = open("/tmp/dhcpd.conf"){|f|f.readlines} + open("/tmp/dhcpd.leases"){|f|f.readlines}
    # Skip comment lines
    conf = conf.delete_if{|line| line=~/^\s*#/}.map{|l| l.chomp}.join("")
    conf.scan(/host\s+(\S+\s*\{[^}]+\})/) do |h|
      key, body = h[0].match(/^(\S+)\s*\{([^\}]+)/)[1,2]
      ip = mac = nil
      body.scan(/([^;]+);/) do |d|
        if    match = d[0].match(/hardware\s+ethernet\s(\S+)/)
          mac = match[1]
        elsif match = d[0].match(/deleted\s(\S+)/)
          scope[key].delete if scope.has_key? key
        elsif match = d[0].match(/fixed-address\s(\S+)/)
          ip = match[1]
          if ip=~/^\D/
            ip = Resolv.getaddress ip rescue nil
            mac = nil if ip.nil?
          end
        end
        if mac and ip and Subnet.contains? scopeIpAddress, ip 
          scope[ip] = mac
          mac = ip = nil
        end
      end
    end
    true
  end


  # Access a hosts DHCP reservation and replace the mac value with a hash which also includes additional DHCP options
  # This is alpha level code and is only implemented for MSDHCP servers
  # [+ip+] : String containing the IP Address
  def getDetails ip
    return nil
    scopeIpAddress = Subnet.find_subnet(ip).dhcp.address 
    #TODO: integrate with GetDetails method
    logger.debug "Finding DHCP data for #{ip}"
    response = invoke "query reservation", nil, "CommandName=/ShowReservedOptionValue&ScopeIPAddress=#{scopeIpAddress}&ReservedIP=#{ip}"
    return if response[2] =~/not a reserved client/  # The machine had no reservation so do nothing

    scopeOptions = {}
    optionId = nil
    # Replace the key -> macaddress with key -> {:mac => value}
    mac = self[scopeIpAddress][ip]
    mac = mac[:mac] if mac.is_a?(Hash)
    self[scopeIpAddress][ip] = {:mac => mac}
    # Merge the scope options into each new reservation
    self[scopeIpAddress][ip].update scopeOptions

    # Add any host specific options replacing any scope level options
    response.each do |line|
      line.chomp
      break if line.match(/^Command completed/)
      if optionIdMatch = line.match(/OptionId : (\d+)/)
        optionId = optionIdMatch[1]
        next
      end
      # TODO: generalise for  element values containing spaces
      if optionValue = line.match(/Option Element Value = (\S+)/) and optionValue = optionValue[1]
        self[scopeIpAddress][ip][optionId] = optionValue
      end
    end
  end

end# class MSDHCPServer
if __FILE__ == $0
  # TODO Generated stub
end
