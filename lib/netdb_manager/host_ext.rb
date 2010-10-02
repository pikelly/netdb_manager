module NetdbManager
  def self.included(base)
    base.extend  ClassMethods
    base.send :include, InstanceMethods
  end

  module InstanceMethods
    def transactional_update
      logger.error "We updated the netdbs"
      puts "We updated the netdbs"
      errors.add_to_base "Failed to update the netwok databases"
      raise ActiveRecord::Rollback
      false
    end
  end

  module ClassMethods
    def networkdb_manager
      after_save  :transactional_update
    end
    def update_netdbs
    end
  end
end

# And yes we need to put this in ActiveRecord and NOT Host
ActiveRecord::Base.send :include, NetdbManager
