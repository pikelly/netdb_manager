# Patch the host with a transactional update facility that we use to hook our update code
require 'netdb_manager/active_record_ext'

ActionController::Base.prepend_view_path(File.join(File.dirname(__FILE__), '..', 'app', 'views')) 

# Our code overrides the application code
Engines.disable_application_code_loading = true

# If we define a view then this is the one we should use.
Engines.disable_application_view_loading = true
