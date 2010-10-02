Dir.glob(File.join(File.dirname(__FILE__), "db", "migrate", "*")).each do |file|
  FileUtils.cp file, File.join(Rails.root, "db", "migrate"), :verbose => true
end
puts "Please run rake db:migrate from the root of your installation"
puts "This will add support for vendors, servertypes and network databases"
