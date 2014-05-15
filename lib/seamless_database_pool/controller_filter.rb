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
  #     include SeamlessDatabasePool::ControllerFilter
  #     use_database_pool :persistent, except: [:update, :delete]
  #     ...

  module ControllerFilter
    extend ActiveSupport::Concern

    module ClassMethods
      # Call this method to set up the connection types that will be used for your
      # actions. Pass connection type in the first argument (:master, :persistent, or
      # :random). It will define method for around filter and apply it
      # with `around_filter`. You can also pass any options supported by
      # `around_filter`.
      def use_database_pool(*args)
        options = args.extract_options!
        pool = args.first
        method_name = :"use_#{"#{pool}_" if pool}database_pool"
        unless method_defined?(method_name)
          define_method(method_name) do |&block|
            read_pool_method = session[:next_request_db_connection]
            session.delete(:next_request_db_connection) if read_pool_method
            read_pool_method ||= pool || custom_database_pool
            SeamlessDatabasePool.set_read_only_connection_type(read_pool_method) do
              instance_eval(&block)
            end
          end

          protected method_name
        end

        around_filter method_name, options
      end

      def skip_use_database_pool(*args)
        options = args.extract_options!
        pool = args.first
        if pool
          skip_around_filter :"use_#{pool}_database_pool", options
        else
          READ_CONNECTION_METHODS.each do |pool|
            skip_around_filter :"use_#{pool}_database_pool", options
          end
          skip_around_filter :use_database_pool, options
        end
      end
    end

    protected
      def redirect_to(*)
        if SeamlessDatabasePool.read_only_connection_type(nil) == :master
          use_master_db_connection_on_next_request
        end
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
