require 'hobo'
require 'openid'
require 'openid_authenticated_user'
require 'openid_user_controller'
require 'add_openid_routes'

class ActionController::Base
  
  def self.hobo_openid_user_controller(model=nil)
    include Hobo::ModelController
    self.model = model if model
    include Hobo::OpenidUserController
    include OpenID
  end
  
end

class ActiveRecord::Base
  
  def self.hobo_openid_user_model
    include Hobo::Model
    include Hobo::OpenidAuthenticatedUser
  end
  
end
