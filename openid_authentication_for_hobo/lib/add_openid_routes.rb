module Hobo
  
  class << self
    
    def add_openid_routes(map)
      begin 
        ActiveRecord::Base.connection.reconnect! unless ActiveRecord::Base.connection.active?
      rescue
        # No database, no routes
        return
      end
      
      require "#{RAILS_ROOT}/app/controllers/application" unless Object.const_defined? :ApplicationController
      require "#{RAILS_ROOT}/app/assemble.rb" if File.exists? "#{RAILS_ROOT}/app/assemble.rb"
      
      for model in Hobo.models
        controller_name = "#{model.name.pluralize}Controller"
        controller = controller_name.constantize if (Object.const_defined? controller_name) || 
          File.exists?("#{RAILS_ROOT}/app/controllers/#{controller_name.underscore}.rb")
          
        if controller
          web_name = model.name.underscore.pluralize.downcase

          if controller < Hobo::ModelController
            map.resources web_name, :collection => { :completions => :get }
            
            if controller < Hobo::OpenidUserController
              prefix = web_name == "users" ? "" : "#{web_name.singularize}_"
              map.named_route("#{web_name.singularize}_login", "#{prefix}login",
                              :controller => web_name, :action => 'login')
              map.named_route("#{web_name.singularize}_complete", "#{prefix}complete",
                              :controller => web_name, :action => 'complete')
              map.named_route("#{web_name.singularize}_logout", "#{prefix}logout",
                              :controller => web_name, :action => 'logout')
            end
          end
        end
      end
    end


  end

end
