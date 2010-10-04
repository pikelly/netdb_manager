class Servertype < ActiveRecord::Base
  has_many :netdbs

  validates_uniqueness_of :name
  validates_presence_of :name
end

