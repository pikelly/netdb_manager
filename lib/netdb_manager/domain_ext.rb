module NetsvcManager
  module DomainExtensions
    def self.included(base) #:nodoc:
      base.extend  ClassMethods
      base.send :include, InstanceMethods
      base.class_eval do
        belongs_to :dns, :class_name => 'Netsvc'
      end
    end
    
    module InstanceMethods
  
    end
    
    module ClassMethods
      
    end
  end
end
Domain.send :include, NetsvcManager::DomainExtensions
