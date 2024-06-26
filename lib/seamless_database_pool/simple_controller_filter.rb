module SeamlessDatabasePool
  # This module provides a simple method of declaring which read pool connection type should
  # be used for various ActionController actions. To use it, you must first mix it into
  # you controller and then call use_database_pool to configure the connection types. Generally
  # you should just do this in ApplicationController and call use_database_pool in your controllers
  # when you need different connection types.
  #
  # Example:
  #
  #   ApplicationController < ActionController::Base
  #     include SeamlessDatabasePool::SimpleControllerFilter
  #     use_database_pool :persistent, except: [:update, :delete]
  #     ...

  module SimpleControllerFilter
    extend ActiveSupport::Concern

    class_methods do
      # Call this method to set up the connection types that will be used for your
      # actions. Pass connection type in the first argument (:master, :persistent, or
      # :random). It will define method for around filter and apply it
      # with `around_filter`. You can also pass any options supported by
      # `around_filter`.
      def use_database_pool(pool, **options)
        method_name = :"use_#{pool}_database_pool"
        define_method(method_name) do |&block|
          read_pool_method = session.delete(:next_request_db_connection) || pool
          SeamlessDatabasePool.set_read_only_connection_type(read_pool_method, &block)
        end
        protected method_name
        around_action method_name, options
      end

      def skip_use_database_pool(pool = nil, **options)
        if pool
          skip_around_action :"use_#{pool}_database_pool", options
        else
          READ_CONNECTION_METHODS.each { |pool| skip_use_database_pool(pool, **options) }
        end
      end
    end

    protected

    def redirect_to(*)
      use_master_db_connection_on_next_request if SeamlessDatabasePool.read_only_connection_type(nil) == :master
      super
    end

    # Force the master connection to be used on the next request. This is very
    # useful for the Post-Redirect pattern where you post a request to your save
    # action and then redirect the user back to the edit action. By calling this
    # method, you won't have to worry if the replication engine is slower than
    # the redirect. Normally you won't need to call this method yourself as it
    # is automatically called when you perform a redirect from within a master
    # connection block. It is made available just in case you have special needs
    # that don't quite fit into this module's default logic.
    def use_master_db_connection_on_next_request
      session[:next_request_db_connection] = :master if session
    end
  end
end
