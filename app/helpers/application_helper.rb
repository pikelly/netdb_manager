module ApplicationHelper
  def settings_dropdown
    choices = [
     ['Additional Settings', ""],
     ['Architectures',       architectures_url],
     ['Domains',             domains_url],
     ['Environments',        environments_url],
     ["External Variables",  lookup_keys_url],
     ['Global Parameters',   common_parameters_url],
     ['Hardware Models',     models_url],
     ['Host Groups',         hostgroups_url],
     ['Installation Medias', medias_url],
     ['LDAP Authentication', auth_source_ldaps_url],
     ['Operating Systems',   operatingsystems_url],
     ['Partition Tables',    ptables_url],
     ['Puppet Classes',      puppetclasses_url],
     ['Subnets',             subnets_url]
     ]
     choices += [
     ['Users',               users_url],
     ['Usergroups',          usergroups_url]
     ] if  SETTINGS[:login]

     concat(
      content_tag(:select, :id => "settings_dropdown") do
       options_for_select choices, :selected => @controller.request.url
      end
     )
     concat(
      observe_field('settings_dropdown', :function => "window.location.href = value;")
     )
  end
end
