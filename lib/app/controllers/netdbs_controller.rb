class NetdbsController < ApplicationController
  layout 'standard'

  active_scaffold :netdb do |config|
    config.label = "Network Database"
    config.actions = [:list,:delete, :search, :create, :show, :update]
    config.columns = [:name, :address, :vendor, :servertype]
    columns[:servertype].label = "Service"
    list.sorting = {:name => 'ASC' }
    config.columns[:vendor].form_ui  = :select
    config.columns[:servertype].form_ui  = :select

    # Deletes require a page update so as to show error messsages
    config.delete.link.inline = false
  end
end
