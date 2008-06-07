require 'openid'
require 'openid/extensions/sreg'
require 'openid/extensions/pape'
require 'openid/store/filesystem'

module Hobo

  module OpenidUserController

    class << self
      def included(base)
        base.skip_before_filter :login_required, :only => [:login, :complete]
        base.class_eval do
          include_taglib "rapid_openid_user_pages", :plugin => "openid_authentication_for_hobo"

          show_action :account
        end
      end
    end
    
    def login; hobo_login; end
    def complete; hobo_complete; end

    def logout; hobo_logout; end
    
    private
    
    def hobo_login(options={})
      @user_model = model

      options.reverse_merge!(:return_to => url_for(:action => :complete))
      
      if request.post?
        openid = params[:login]
        begin
          oidreq = openid_consumer.begin openid
        rescue OpenID::OpenIDError => e
          flash[:error] = "Discovery failed for #{openid}: #{e}"
          redirect_to homepage_url
        end

        return_to = options[:return_to]
        trust_root = homepage_url
        
        # If this is going to be a new account...
        unless model.find_by_identity_url(OpenID.normalize_url(openid))
          required_sreg_keys = model.simple_registration_mappings[:required]
          optional_sreg_keys = model.simple_registration_mappings[:optional]

          
          required_sreg_keys &&= required_sreg_keys.keys.map &:to_s
          optional_sreg_keys &&= optional_sreg_keys.keys.map &:to_s

          if required_sreg_keys || optional_sreg_keys
            sregreq = OpenID::SReg::Request.new(required_sreg_keys, optional_sreg_keys)
            if !options[:policy_url].blank?
              sregreq.policy_url = options[:policy_url]
            elsif defined_route?("policy")
              sregreq.policy_url = policy_url
            end
            oidreq.add_extension(sregreq)
          end

        end
        
        redirect_to oidreq.redirect_url trust_root, return_to
      end
      
    end

    def hobo_complete(options={})
      @user_model = model

      options.reverse_merge!(:success_notice => "You have logged in",
                             :failure_notice => "Verification failed",
                             :cancellation_notice => "Verification cancelled",
                             :setup_needed_notice => "OpenID server reports setup is needed",
                             :new_user_failure_notice => "Could not create a new user account",
                             :redirect_to => { :controller => "front", :action => "index" })

      user = nil
      
      current_url = url_for(:action => 'complete', :only_path => false)
      # un-munge params array
      parameters = params.reject{|k,v|request.path_parameters[k]}
            
      response = openid_consumer.complete parameters, current_url

      case response.status
      when OpenID::Consumer::SUCCESS
        openid = response.identity_url
        user = model.find_by_identity_url(openid)
        
        ## If a user account doesn't exist yet, then create one
        if user.nil?
          
          # Generate parameters for new user record
          user_attrs = { model.login_attribute => openid }

          sreg = OpenID::SReg::Response.from_success_response(response)

          model.simple_registration_mappings.each do |set,mappings|
            mappings.each do |key,col|
              user_attrs[col] = sreg[key.to_s]
            end
          end
          
          user = model.new(user_attrs)

          unless user.save!
            flash[:notice] = options[:new_user_failure_notice]
            user = nil
          end
          
        end
        
      when OpenID::Consumer::FAILURE
        flash[:notice] = options[:failure_notice]
        
      when OpenID::Consumer::CANCEL
        flash[:notice] = options[:cancellation_notice]

      when OpenID::Consumer::SETUP_NEEDED
        flash[:notice] = options[:setup_needed_notice]

      else
        flash[:notice] = "Unknown response from OpenID server."
      end

      if user.nil?
        flash[:notice] ||= options[:failure_notice]
      else
        old_user = current_user
        self.current_user = user
        
        # If supplied, a block can be used to test if this user is
        # allowed to log in (e.g. the account may be disabled)
        if block_given? && !yield
          # block returned false - cancel this login
          self.current_user = old_user
        else
          if params[:remember_me] == "1"
            current_user.remember_me
            create_auth_cookie
          end
          flash[:notice] ||= options[:success_notice]
          unless performed?
            redirect_back_or_default(options[:redirect_to] || 
                                     url_for(:controller => "front",
                                             :action => "index"))
          end
        end
      end
      redirect_to :action => "login" unless performed?
    end
    
    def hobo_logout(options={})
      options = options.reverse_merge(:notice => "You have been logged out.",
                                      :redirect_to => base_url)
        
      current_user.forget_me if logged_in?
      cookies.delete :auth_token
      reset_session
      flash[:notice] = options[:notice]
      redirect_back_or_default(options[:redirect_to])
    end

    private
    
    # Get the OpenID::Consumer object.
    def openid_consumer
      # create the OpenID store for storing associations and nonces,
      # putting it in your app's db directory
      # you can also use database store.
      store_dir = Pathname.new(RAILS_ROOT).join('db').join('openid-store')
      store = OpenID::Store::Filesystem.new(store_dir)
      
      return OpenID::Consumer.new(session, store)
    end
    
  end
  
end
