class Servertype < ActiveRecord::Base
  has_many :netsvcs

  validates_uniqueness_of :name
  validates_presence_of :name
end

