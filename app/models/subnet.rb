class Subnet < ActiveRecord::Base
  has_many :hosts
  has_many :sps, :class_name => 'Host', :foreign_key => 'sp_subnet_id'
  belongs_to :domain
  belongs_to :dhcp, :class_name => 'Netdb'

  validates_presence_of   :number, :mask, :domain, :name
  validates_uniqueness_of :number
  validates_format_of     :number,     :with => /(\d{1,3}\.){3}\d{1,3}/, :message => "self.number is invalid"
  validates_format_of     :mask,       :with => /(\d{1,3}\.){3}\d{1,3}/
  validates_uniqueness_of :name, :scope => :domain_id
  validates_associated    :domain

  before_destroy Ensure_not_used_by.new(:hosts, :sps)
  validate_on_create :must_be_unique_per_site

  after_create :invalidate_cache

  # Subnets are sorted on their priority value
  # [+other+] : Subnet object with which to cmpare ourself
  # +returns+ : Subnet object with higher presidence
  def <=> (other)
   self.priority <=> other.priority
  end

  def invalidate_cache
    return true if RAILS_ENV == "test"
    ApplicationController.reload_network_data if memcache_used?
  end
  
  # Subnets are displayed in the form of their network number/network mask
  def to_label
    "#{domain.name}: #{number}/#{mask}"
  end

  # If a subnet object exists then it can never be empty
  #+RETURNS+ : Boolean false
  def empty?
    false
  end
  
  # Given an IP returns the subnet that contains that IP
  # [+ip+] : "doted quad" string
  # Returns : Subnet object or nil if not found
  def self.subnet_for(ip)
    for subnet in Subnet.all
      return subnet if subnet.contains? IPAddr.new(ip)
    end
    nil
  end
  
  def self.contains? scopeIpAddress, ip
    Subnet.find_by_number(scopeIpAddress).contains? IPAddr.new(ip, Socket::AF_INET)
  end

  def detailedName
    return "#{self.name}@#{self.number}/#{self.mask}"
  end

  # Indicates whether the IP is within this subnet
  # [+ip+] String: Contains 4 dotted decimal values
  # Returns Boolean: True if if ip is in this subnet
  def contains? ip
    IPAddr.new("#{number}/#{mask}", Socket::AF_INET).include? IPAddr.new(ip, Socket::AF_INET)
  end

# Returns the next free IP address in this subnet It checks DNS, DHCP and the database to work this out
  # [+dns+]    : DNSServer object
  # [+dhcp+]   : DHCPServer object
  # [+logger+] : A rails logger object
  # +returns+  : String containing dotted quad, or nil if there is no free IP
  def nextIp dns, dhcp, site, logger

    ip = IPAddr.new(number + "/" + mask)
    
    # If we have no admin rights then return the subnet number + 1 as you may not use an offset of zero
    return (ip.succ) if dns.nil? or dhcp.empty?

    # Scan through this subnet and find the first free slot
    # Examples: 2,4-5,60-70,172.29.102.1-254

    if self.ranges
      ranges = self.ranges
    else
      s         = ip.suc.succ                # The network number + 2
      f         = ip.to_range[1]             # The last ip in the range
      ranges    = "#{s}-#{f}"
    end
    # Find possible hostname-number collisions
    numbers = Host.find(:all, :conditions => "hostname like \'#{site}%\'").map{|h| m = h.hostname.match(/\d+$/); m ? m[0] : nil}.compact.map{|n| n.to_i.to_s}
    unless ranges.empty?
      # Convert a single "number" to "number-number"
      ranges = ranges.split(",").map{|r| r.match(/^[\d\.]+$/) ? "#{r}-#{r}" : r}
      # Converts 172.29.100.1-254 to 172.29.100.1-172.29.100.254
      ranges = ranges.collect{|r| (m = r.match(/^(\d+\.\d+\.\d+)\.(\d+)-(\d+)$/)) ? "#{m[1]}.#{m[2]}-#{m[1]}.#{m[3]}" : r }
      # Convert 1-2 to 172.29.100.1-172.29.100.2
      # Note that the last quad is dropped in to replace the last
      ranges = ranges.collect{|r| (m = r.match(/^(\d+)-(\d+)$/)) ? "#{self.number.sub(/\d+$/,m[1])}-#{self.number.sub(/\d+$/,m[2])}" : r }
      ranges.each{|range|
        start, finish = range.split("-").map{|_s, _f| [IPAddr.new(_s), IPAddr.new(_f)]}

        (start..finish).each{|candidate|
          if not DNS::Server::has_ip?(dns[:A], candidate.to_s) and 
             not dhcp[self.number].has_key?(candidate.to_s) and 
             not Host.find_by_ip(candidate.to_s) and 
             not numbers.include?(candidate.to_s) #TODO Is this correct?
            return candidate.to_s
          end
        }
      }
    end
    nil
  end

private
  # Before we save a subnet ensure that we cannot find a subnet at our site with an identical name
  def must_be_unique_per_site
    if self.domain and self.domain.subnets
      unless self.domain.subnets.find_by_name(self.name).nil?
        errors.add_to_base "The name #{self.name} is already in use at #{self.domain.fullname}"
      end
    end
  end

end
