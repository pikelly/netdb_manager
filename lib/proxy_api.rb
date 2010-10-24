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

    def initialize(args)
      @user     = args[:user]     || "admin"
      @password = args[:password] || "changeme"

      @resource = RestClient::Resource.new url,{ :user => user, :password => password,
        :headers => { :accept => :json, :content_type => :json }}
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

    def parse response
      if response == "null" or response.empty?
        []
      else
        JSON.parse(response)
      end
    end

    def _get_ path
      @resource[URI.escape(path)].get.body
    end

    def _post_ payload, path
      @resource[path].post payload
    end

    def _put_ payload, path
      @resource[path].put payload
    end

    def _delete_ path
      @resource[path].delete
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
      @url  = args[:url] || raise("Must provide a URL")
      @url += "/dhcp"
      super args
    end

    def subnets
      parse(_get_(".json"))
    end

    def get subnet, mac
      parse(_get_("#{subnet}/#{mac}.json"))
    end

    def set subnet, mac, args
      parse(_post_(args.merge(:mac => mac), "#{subnet}"))
    end

    def delete subnet, mac
      parse(_delete_("#{subnet}/#{mac}"))
    end
  end

  class DNS < Resource
    def initialize args
      @url  = args[:url] || raise("Must provide a URL")
      @url += "/dns"
      super args
    end
    
    def set key, args
      parse(_post_(args.merge(:fqdn => key), ""))
    end
    
    def delete key
      parse(_delete_("#{key}"))
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