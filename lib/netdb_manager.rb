# Patch the ActionController with a alias_method_chain that loads our modifications to the models
require 'netdb_manager/action_controller_ext'

ActionController::Base.prepend_view_path(File.join(File.dirname(__FILE__), '..', 'app', 'views')) 

# Our code overrides the application code
Engines.disable_application_code_loading = true

# If we define a view then this is the one we should use.
Engines.disable_application_view_loading = true
