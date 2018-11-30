# app/models/user.rb
class User < ApplicationRecord
  has_many_attached :pictures
end
