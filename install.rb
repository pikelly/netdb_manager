#!/usr/bin/ruby
require 'fileutils'
root =  File.join(File.dirname(__FILE__),"..", "..", "..")
Dir.glob(File.join(File.dirname(__FILE__), "lib", "db", "migrate", "*")).each do |file|
  FileUtils.cp file, File.join(root, "db", "migrate"), :verbose => true
end
puts "********************************************************************"
puts "Please run rake db:migrate from the root of your installation"
puts "This will add support for vendors, servertypes and network databases"
puts "********************************************************************"

routes = File.join(root, "config", "routes")
new_routes = File.join(root, "config", "routes.new")
unless `grep subnets #{routes}`
  File.open(routes, "r") do |src|
    File.open(new_routes, "w") do |dst|
      line = src.readline
      dst.write("map.NetsvcManagers") if line.match(/Routes.draw/)
      dst.write line
    end
  end
  FileUtils.mv src, dst
end