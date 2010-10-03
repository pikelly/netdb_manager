module NetdbManager
  #:nodoc:
  module Routing
    #:nodoc:
    module MapperExtensions
      def NetdbManagers
        @set.add_route("/subnets", {:controller => "subnets", :action => "index"})
      end
    end
  end
end
ActionController::Routing::RouteSet::Mapper.send :include, NetdbManager::Routing::MapperExtensions 
