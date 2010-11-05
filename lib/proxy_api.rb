require "rest_client"
require "json"
require "uri"
require "ostruct"

# work around of open struct not to send its object id
OpenStruct.__send__(:define_method, :id) { @table[:id] || self.object_id }

module ProxyAPI
  
  module Util
    def strip_hash_name(hash, name = hash_name)
      hash.collect{|r| r[name]}
    end
  end

  class Resource
    attr_reader :url, :user, :password
    include Util
    attr_accessor :error

    def initialize(args)
      @user     = args[:user]     || "admin"
      @password = args[:password] || "changeme"

      @resource = RestClient::Resource.new url,{ :user => user, :password => password,
        :headers => { :accept => :json, :content_type => :json }}
    end

    def hostname
      match = @resource.to_s.match(/:\/\/([^\/:]+)/)
      match ? match[1] : "hostname in #{@resource}"
    end

    def list
      strip_hash_name(parse(get(path_prefix)))
    end

    def find_by_name name
      list.each do |resource|
        return resource if resource["name"] == name
      end
    end

    private

    def path_prefix
      self.class.to_s.gsub(/.*::/,"")
    end

    # Decodes the JSON reply if no HTTP error has been detected
    # If an HTTP error is received then the error messsage is saves into @error
    # Returns: Response, if the operation is GET, or true for POST, PUT and DELETE.
    #      OR: false if a HTTP error is detected
    def parse reply
      if reply[0].code == "200"
        if reply[1].size > 2
          JSON.parse(reply[1])
        else
          true
        end
      else
        @error = reply[1]
        false
      end
    end

    # Perform GET operation on the supplied path
    # Returns: Array [result, response]
    #  result  : Object with a code method which is a HTTP error code
    #  response: HTTP body
    def _get_ path
      @resource[URI.escape(path)].get{|response, request, result| [result, response] }
    rescue Exception => e
      [ OpenStruct.new(:code => "500"), e.message =~ /getaddrinfo/ ? "Unable to locate #{hostname}" : e.message]
    end

    # Perform POST operation with the supplied payload on the supplied path
    # Returns: Array [result, response]
    #  result  : Object with a code method which is a HTTP error code
    #  response: HTTP body
    def _post_ payload, path
      @resource[path].post(payload){|response, request, result| [result, response] }
    rescue Exception => e
      [ OpenStruct.new(:code => "500"), e.message =~ /getaddrinfo/ ? "Unable to locate #{hostname}" : e.message]
    end

    # Perform PUT operation with the supplied payload on the supplied path
    # Returns: Array [result, response]
    #  result  : Object with a code method which is a HTTP error code
    #  response: HTTP body
    def _put_ payload, path
      @resource[path].put(payload){|response, request, result| [result, response] }
    rescue Exception => e
      [ OpenStruct.new(:code => "500"), e.message =~ /getaddrinfo/ ? "Unable to locate #{hostname}" : e.message]
    end

    # Perform DELETE operation on the supplied path
    # Returns: Array [result, response]
    #  result  : Object with a code method which is a HTTP error code
    #  response: HTTP body
    def _delete_ path
      @resource[path].delete{|response, request, result| [result, response] }
    rescue Exception => e
      [ OpenStruct.new(:code => "500"), e.message =~ /getaddrinfo/ ? "Unable to locate #{hostname}" : e.message]
    end

    def hash_name
      path_prefix.gsub(/^\//,"").chomp("s") if path_prefix =~ /s$/
    end

    def opts
      {:url => url, :user => user, :password => password }
    end
  end

  class DHCP < Resource
    def initialize args
      @url  = args[:url] + "/dhcp" || raise("Must provide a URL")
      super args
    end

    # Retrive the Server's subnets
    # Returns: Array of Hashes or false
    # Example [{"network":"192.168.11.0","netmask":"255.255.255.0"},{"network":"192.168.122.0","netmask":"255.255.255.0"}]
    def subnets
      parse(_get_(""))
    end

    # Retrieves a DHCP entry
    # [+subnet+] : String in dotted decimal format
    # [+mac+]    : String in coloned sexpulet format
    # Returns    : Hash or false
    def get subnet, mac
      parse(_get_("#{subnet}/#{mac}"))
    end

    # Sets a DHCP entry
    # [+subnet+] : String in dotted decimal format
    # [+mac+]    : String in coloned sexpulet format
    # [+args+]   : Hash containing DHCP values. The :mac key is taken from the mac parameter
    # Returns    : Boolean status
    def set subnet, mac, args
      parse(_post_(args.merge(:mac => mac), "#{subnet}"))
    end

    # Deletes a DHCP entry
    # [+subnet+] : String in dotted decimal format
    # [+mac+]    : String in coloned sexpulet format
    # Returns    : Boolean status
    def delete subnet, mac
      parse(_delete_("#{subnet}/#{mac}"))
    end
  end

  class DNS < Resource
    def initialize args
      @url  = args[:url] + "/dns" || raise("Must provide a URL")
      super args
    end
    
    # Sets a DNS entry
    # [+fqdn+] : String containing the FQDN of the host
    # [+args+] : Hash containing :value and :type: The :fqdn key is taken from the fqdn parameter
    # Returns  : Boolean status
    def set fqdn, args
      parse(_post_(args.merge(:fqdn => fqdn), ""))
    end
    
    # Deletes a DNS entry
    # [+key+] : String containing either a FQDN or a dotted quad plus .in-addr.arpa.
    # Returns    : Boolean status
    def delete key
      parse(_delete_("#{key}"))
    end
  end

  class TFTP < Resource
    def initialize args
      @url  = args[:url] + "/tftp" || raise("Must provide a URL")
      super args
    end

    def set mac, args
      parse(_post_(args, mac))
    end

    def delete mac
      parse(_delete_("#{mac}"))
    end

    def fetch_boot_file args
      parse(_post_(args, "fetch_boot_file"))
    end
  end
end

if __FILE__.gsub(/\.\//, "") == $0
  dhcp = ProxyAPI::DHCP.new(:url => "http://localhost:4567")
  subnets = dhcp.subnets
  entry = dhcp.get("192.168.122.0", "22:33:44:55:66:11")
  unless entry.empty?
    dhcp.delete("192.168.122.0", "22:33:44:55:66:11")
  end
  dhcp.set("192.168.122.0", "22:33:44:55:66:11", {:hostname => "brsla804.brs.example.com", :nextserver => "192.168.122.1", :filename => "kickstart/pxelinux.0", 
                                                  :name     => "brsla804.brs.example.com", :ip => "192.168.122.4"})
  dns = ProxyAPI::DNS.new(:url => "http://localhost:4567")
  status = dns.set("brsla804.brs.example.com", :value => "192.168.122.4", :type => :A)
  status = dns.set("4.122.168.192.in-addr.arpa", :value => "brsla804.brs.example.com", :type => :PTR)
#  status = dns.delete("brsla804.brs.example.com")
#  status = dns.delete("4.122.168.192.in-addr.arpa")
  true
end