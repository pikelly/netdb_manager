ActiveSupport::Dependencies.load_once_paths.delete File.dirname(__FILE__)
# Patch the host with a transactional update facility that we use to hook our update code
require 'netdb_manager/host_ext'

# Rails Engines works against us in some ways as it ensures that the last loaded module overrides the first. 
# As the application's version of application_helper.rb is loaded last it overrides our overrides.
# Never mind, just load our overrides again, as the last loaded module. Maybe I should drop engines. . . . 
require_or_load File.join(File.dirname(__FILE__), '..',"app", "helpers", "application_helper.rb")

#HostsController.prepend_view_path(File.join(File.dirname(__FILE__), '..', 'app', 'views')) 

# If we define a view then this is the one we should use.
Engines.disable_application_view_loading = true
