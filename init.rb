#require_dependency File.join(File.dirname(__FILE__), "..", "..", "..", "config", "initializers", "foreman")
require 'netdb_manager'
ActiveSupport::Dependencies.load_once_paths.delete lib_path