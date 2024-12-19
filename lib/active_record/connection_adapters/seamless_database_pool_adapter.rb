require "active_record/database_configurations"

module ActiveRecord
  module ConnectionHandling # :nodoc:
    # legacy way (up to 7.1)
    def seamless_database_pool_connection(config)
      seamless_database_pool_adapter_class.new(config)
    end

    # rails 7.1 (but in fact not used in rails?)
    def seamless_database_pool_adapter_class
      ActiveRecord::ConnectionAdapters::SeamlessDatabasePoolAdapter
    end

    # rails 7.2+
    if ConnectionAdapters.respond_to?(:register)
      ConnectionAdapters.register(
        "seamless_database_pool",
        "ActiveRecord::ConnectionAdapters::SeamlessDatabasePoolAdapter",
        "active_record/connection_adapters/seamless_database_pool_adapter"
      )
    end

    if ActiveRecord.gem_version <= '7.1'
      # known builtin adapters
      # TODO: remove ADAPTER_TO_CLASS_NAME_MAP
      {
        sqlite3: ["ActiveRecord::ConnectionAdapters::SQLite3Adapter", "active_record/connection_adapters/sqlite3_adapter"],
        mysql2: ["ActiveRecord::ConnectionAdapters::Mysql2Adapter", "active_record/connection_adapters/mysql2_adapter"],
        postgresql: ["ActiveRecord::ConnectionAdapters::PostgreSQLAdapter", "active_record/connection_adapters/postgresql_adapter"]
      }.each_pair do |known_adapter, (class_name, path_to_adapter)|
        define_method(:"#{known_adapter}_adapter_class") do
          require path_to_adapter
          # rails rescues LoadError and provides more info
          Object.const_get(class_name)
        end
      end
    end
  end

  class Base
    class << self
      def establish_adapter(adapter)
        raise AdapterNotSpecified.new('database configuration does not specify adapter') unless adapter
        raise AdapterNotFound.new('database pool must specify adapters') if adapter == 'seamless_database_pool'

        adapter_method = "#{adapter}_connection"
        return if respond_to?(adapter_method)
        return if ActiveRecord::ConnectionAdapters.respond_to?(:resolve)

        begin
          require 'rubygems'
          gem "activerecord-#{adapter}-adapter"
          require "active_record/connection_adapters/#{adapter}_adapter"
        rescue LoadError
          begin
            require "active_record/connection_adapters/#{adapter}_adapter"
          rescue LoadError
            raise LoadError.new(
              "Please install the #{adapter} adapter: `gem install activerecord-#{adapter}-adapter` (#{$!})"
            )
          end
        end

        return if respond_to?(adapter_method)

        raise AdapterNotFound, "database configuration specifies nonexistent #{adapter} adapter"
      end
    end

    module SeamlessDatabasePoolBehavior
      # Force reload to use the master connection since it's probably being called for a reason.
      def reload(*args)
        SeamlessDatabasePool.use_master_connection do
          super(*args)
        end
      end
    end

    prepend SeamlessDatabasePoolBehavior
  end

  module ConnectionAdapters
    class SeamlessDatabasePoolAdapter < AbstractAdapter
      attr_reader :read_connections, :master_connection

      class << self
        def new(*args)
          return super unless self == SeamlessDatabasePoolAdapter

          config_or_deprecated_connection = args.first
          config = (
            config_or_deprecated_connection.is_a?(Hash) ? config_or_deprecated_connection : args[3]
          ).deep_symbolize_keys
          master_adapter = config.dig(:master, :adapter) || config.dig(:master, :url)&.then { URI.parse(_1).scheme } || config.dig(:pool_adapter)
          master_connection_class = if ActiveRecord::ConnectionAdapters.respond_to?(:resolve) # rails 7.2+
                                      ActiveRecord::ConnectionAdapters.resolve(master_adapter)
                                    elsif ActiveRecord::Base.respond_to?(:"#{master_adapter}_adapter_class")
                                      ActiveRecord::Base.public_send(:"#{master_adapter}_adapter_class") # rails 7.1
                                    else
                                      raise "Cannot resolve class for master adapter #{master_adapter}, does it implement rails 7.1+ api?"
                                    end
          adapter_class(master_connection_class).new(*args)
        end

        def prepare_config(config)
          config = config.with_indifferent_access
          default_config = { pool_weight: 1 }.merge(config.merge(adapter: config[:pool_adapter])).with_indifferent_access
          default_config.delete(:master)
          default_config.delete(:read_pool)
          default_config.delete(:pool_adapter)

          master_config = default_config.merge(config[:master]).with_indifferent_access
          if (url = master_config.delete(:url))
            master_config.merge!(ActiveRecord::DatabaseConfigurations::ConnectionUrlResolver.new(url).to_hash)
          end

          read_configs = config[:read_pool]&.map do |read_config|
            read_config = default_config.merge(read_config).with_indifferent_access
            if (url = read_config.delete(:url))
              read_config.merge!(ActiveRecord::DatabaseConfigurations::ConnectionUrlResolver.new(url).to_hash)
            end
            read_config[:pool_weight] = read_config[:pool_weight].to_i

            read_config
          end

          [master_config, read_configs || []]
        end

        def instantiate_sub_adapter(config, name = 'master')
          adapter_name = config[:adapter]
          ActiveRecord::Base.establish_adapter(adapter_name) # see above, todo: refactor

          if ActiveRecord::ConnectionAdapters.respond_to?(:resolve)
            ActiveRecord::ConnectionAdapters.resolve(adapter_name).new(config)
          else
            ActiveRecord::Base.send(:"#{adapter_name}_connection", config)
          end.tap do |conn|
            SeamlessDatabasePool.connection_names[conn.object_id] = name
          end
        end

        # Create an anonymous class that extends this one and proxies methods to the pool connections.
        def adapter_class(master_connection_class)
          raise AdapterNotFound.new('database pool must not be recursive') if master_connection_class <= SeamlessDatabasePoolAdapter

          adapter_class_name = master_connection_class.name.demodulize
          return const_get(adapter_class_name) if const_defined?(adapter_class_name, false)

          # Define methods to proxy to the appropriate pool
          read_only_methods = %i[select select_rows execute tables columns]
          clear_cache_methods = %i[insert update delete with_raw_connection]

          # Get a list of all methods redefined by the underlying adapter. These will be
          # proxied to the master connection.
          master_methods = []
          override_classes = (master_connection_class.ancestors - AbstractAdapter.ancestors)
          override_classes.each do |connection_class|
            master_methods.concat(connection_class.public_instance_methods(false))
            master_methods.concat(connection_class.protected_instance_methods(false))
            master_methods.concat(connection_class.private_instance_methods(false))
          end
          master_methods = master_methods.collect(&:to_sym).uniq
          master_methods -= (
            public_instance_methods(false) + protected_instance_methods(false) + private_instance_methods(false)
          )
          master_methods -= read_only_methods
          master_methods -= %i[select_all select_one select_value select_values]
          master_methods -= clear_cache_methods

          klass = Class.new(self)
          (master_connection_class.singleton_class.included_modules -
            AbstractAdapter.singleton_class.included_modules).each { klass.extend(_1) }

          master_methods.each do |method_name|
            klass.class_eval <<-RUBY, __FILE__, __LINE__ + 1
              ruby2_keywords def #{method_name}(*args, &block)
                use_master_connection do
                  return proxy_connection_method(master_connection, :#{method_name}, :master, *args, &block)
                end
              end
            RUBY
          end

          clear_cache_methods.each do |method_name|
            klass.class_eval <<-RUBY, __FILE__, __LINE__ + 1
              ruby2_keywords def #{method_name}(*args, &block)
                clear_query_cache if query_cache_enabled
                use_master_connection do
                  return proxy_connection_method(master_connection, :#{method_name}, :master, *args, &block)
                end
              end
            RUBY
          end

          read_only_methods.each do |method_name|
            klass.class_eval <<-RUBY, __FILE__, __LINE__ + 1
              ruby2_keywords def #{method_name}(*args, &block)
                connection = @use_master ? master_connection : current_read_connection
                proxy_connection_method(connection, :#{method_name}, :read, *args, &block)
              end
            RUBY
          end
          klass.send :protected, :select

          const_set(adapter_class_name, klass)

          klass
        end

        # Set the arel visitor on the connections.
        # unused in modern rails (was used in around rails 3)? looks being replaced by `connection.arel_visitor`
        def visitor_for(pool)
          # This is ugly, but then again, so is the code in ActiveRecord for setting the arel
          # visitor. There is a note in the code indicating the method signatures should be updated.
          config = pool.spec.config.with_indifferent_access
          adapter = config[:master][:adapter] || config[:pool_adapter]
          SeamlessDatabasePool.adapter_class_for(adapter).visitor_for(pool)
        end
      end

      def initialize(config_or_deprecated_connection, deprecated_logger = nil, deprecated_connection_options = nil, deprecated_config = nil)
      # def initialize(...)
        # to call super we already need master_connection, so have to deal with config here:
        @config = config_or_deprecated_connection.is_a?(Hash) ? config_or_deprecated_connection : deprecated_config
        master_config, read_configs = self.class.prepare_config(@config)

        pool_weights = {}
        @use_master = nil
        @master_connection = SeamlessDatabasePoolAdapter.instantiate_sub_adapter(master_config, 'master')
        pool_weights[@master_connection] = master_config[:pool_weight].to_i if master_config[:pool_weight].to_i > 0

        super(nil, deprecated_logger, @config)

        @read_connections = []
        read_configs.each_with_index do |read_config, i|
          next unless read_config[:pool_weight] > 0

          conn = SeamlessDatabasePoolAdapter.instantiate_sub_adapter(read_config, "slave_#{i}")
          @read_connections << conn
          pool_weights[conn] = read_config[:pool_weight]
        rescue StandardError => e
          if logger
            logger.error("Error connecting to read connection #{read_config.inspect}")
            logger.error(e)
          end
          raise if defined?(Rails) && Rails.env.test? # nb not all tests have this
          raise
        end
        @read_connections = read_connections.freeze

        @weighted_read_connections = []
        pool_weights.each_pair do |conn, weight|
          weight.times { @weighted_read_connections << conn }
        end
        @available_read_connections = [AvailableConnections.new(@weighted_read_connections)]
      end

      def adapter_name # :nodoc:
        'Seamless_Database_Pool'
      end

      # Returns an array of the master connection and the read pool connections
      def all_connections
        [@master_connection] + @read_connections
      end

      # Get the pool weight of a connection
      def pool_weight(connection)
        @weighted_read_connections.select { |conn| conn == connection }.size
      end

      def requires_reloading?
        false
      end

      def transaction(**options)
        SeamlessDatabasePool.use_master_connection
        super
      end

      def visitor=(visitor)
        all_connections.each { |conn| conn.visitor = visitor }
      end

      def visitor
        master_connection.visitor
      end

      def active?
        if SeamlessDatabasePool.read_only_connection_type == :master
          @master_connection.active?
        else
          do_to_connections(true) do |conn|
            # NB: master connection is here too
            return true if conn.active?
          end
          false
        end
      end

      def reconnect!
        do_to_connections(&:reconnect!)
      end

      def disconnect!
        do_to_connections(&:disconnect!)
      end

      def reset!
        do_to_connections(&:reset!)
      end

      def verify!(*ignored)
        if SeamlessDatabasePool.read_only_connection_type == :master
          @master_connection.verify!(*ignored)
        else
          do_to_connections(true) { |conn| conn.verify!(*ignored) }
        end
      end

      def reset_runtime
        total = 0.0
        do_to_connections { |conn| total += conn.reset_runtime }
        total
      end

      # Get a random read connection from the pool. If the connection is not active, it will attempt to reconnect
      # to the database. If that fails, it will be removed from the pool for one minute.
      def random_read_connection
        weighted_read_connections = available_read_connections
        return master_connection if @use_master || weighted_read_connections.empty?

        weighted_read_connections[rand(weighted_read_connections.length)]
      end

      # Get the current read connection
      def current_read_connection
        SeamlessDatabasePool.read_only_connection(self)
      end

      def using_master_connection?
        !!@use_master
      end

      # Force using the master connection in a block.
      def use_master_connection
        save_val = @use_master
        begin
          @use_master = true
          yield if block_given?
        ensure
          @use_master = save_val
        end
      end

      def to_s
        "#<#{self.class.name}:0x#{object_id.to_s(16)} #{all_connections.size} connections>"
      end

      def inspect
        to_s
      end

      class DatabaseConnectionError < StandardError
      end

      # This simple class puts an expire time on an array of connections. It is used so the a connection
      # to a down database won't try to reconnect over and over.
      class AvailableConnections
        attr_reader :connections, :failed_connection
        attr_writer :expires

        def initialize(connections, failed_connection = nil, expires = nil)
          @connections = connections
          @failed_connection = failed_connection
          @expires = expires
        end

        def expired?
          @expires ? @expires <= Time.now : false
        end

        def reconnect!
          failed_connection.reconnect!
          raise DatabaseConnectionError.new unless failed_connection.active?
        end
      end

      # Get the available weighted connections. When a connection is dead and cannot be reconnected, it will
      # be temporarily removed from the read pool so we don't keep trying to reconnect to a database that isn't
      # listening.
      def available_read_connections
        available = @available_read_connections.last
        return available.connections unless available.expired?

        begin
          @logger&.info('Adding dead database connection back to the pool')
          available.reconnect!
        rescue StandardError => e
          # Couldn't reconnect so try again in a little bit
          if @logger
            @logger.warn('Failed to reconnect to database when adding connection back to the pool')
            @logger.warn(e)
          end
          available.expires = 30.seconds.from_now
          return available.connections
        end

        # If reconnect is successful, the connection will have been re-added to @available_read_connections list,
        # so let's pop this old version of the connection
        @available_read_connections.pop

        # Now we'll try again after either expiring our bad connection or re-adding our good one
        available_read_connections
      end

      def reset_available_read_connections
        @available_read_connections.slice!(1, @available_read_connections.length)
        @available_read_connections.first.connections.each do |connection|
          next if connection.active?

          begin
            connection.reconnect!
          rescue StandardError
            nil
          end
        end
      end

      # Temporarily remove a connection from the read pool.
      def suppress_read_connection(conn, expire)
        available = available_read_connections
        connections = available.reject { |c| c == conn }

        # This wasn't a read connection so don't suppress it
        return if connections.length == available.length

        if connections.empty?
          @logger&.warn('All read connections are marked dead; trying them all again.')
          # No connections available so we might as well try them all again
          reset_available_read_connections
        else
          name = SeamlessDatabasePool.connection_names[conn.object_id]
          @logger&.warn("Removing #{name} from the connection pool for #{expire} seconds")
          # Available connections will now not include the suppressed connection for a while
          @available_read_connections.push(AvailableConnections.new(connections, conn, expire.seconds.from_now))
        end
      end

      private

      ruby2_keywords def proxy_connection_method(connection, method, proxy_type, ...)
        connection.send(method, ...)
      rescue StandardError => e
        # If the statement was a read statement and it wasn't forced against the master connection
        # try to reconnect if the connection is dead and then re-run the statement.
        raise e unless proxy_type == :read && !using_master_connection?

        unless connection.active?
          suppress_read_connection(connection, 30)
          SeamlessDatabasePool.set_persistent_read_connection(self, nil)
          connection = current_read_connection
          SeamlessDatabasePool.set_persistent_read_connection(self, connection)
        end
        proxy_connection_method(connection, method, :retry, ...)
      end

      # Yield a block to each connection in the pool. If the connection is dead, ignore the error
      # unless it is the master connection
      def do_to_connections(suppress = false)
        all_connections.each do |conn|
          yield(conn)
        rescue StandardError => e
          raise e if conn == master_connection && !suppress
        end
        nil
      end
    end
  end
end
