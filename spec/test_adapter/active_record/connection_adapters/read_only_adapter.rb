# frozen_string_literal: true

module ActiveRecord
  module ConnectionHandling
    def read_only_connection(config)
      ConnectionAdapters::ReadOnlyAdapter.new(config)
    end

    if ConnectionAdapters.respond_to?(:register)
      ConnectionAdapters.register(
        "read_only", "ActiveRecord::ConnectionAdapters::ReadOnlyAdapter",
        "active_record/connection_adapters/read_only_adapter"
      )
    end
  end

  module ConnectionAdapters
    class ReadOnlyAdapter < AbstractAdapter
      %w[select select_rows execute tables columns].each do |read_method|
        class_eval <<-RUBY, __FILE__, __LINE__ + 1
          ruby2_keywords def #{read_method}(*args, &block)
            raise "Not Connected" unless @connected
            result = @connection.send(:#{read_method}, *args, &block)
            def result.read_only?
              true
            end
            result
          end
        RUBY
      end

      %w[update insert delete reload create_table drop_table add_index remove_index transaction].each do |write_method|
        class_eval <<-RUBY, __FILE__, __LINE__ + 1
          def #{write_method}(*args, **kwargs, &block)
            raise NotImplementedError.new("Master method '#{write_method}' called on read only connection")
          end
        RUBY
      end

      def initialize(config)
        real_adapter = config.delete('real_adapter')
        @connection = if ActiveRecord::ConnectionAdapters.respond_to?(:resolve) # rails 7.2
                        ActiveRecord::ConnectionAdapters.resolve(real_adapter).new(config.merge('adapter' => real_adapter))
                      else
                        ActiveRecord::Base.send(:"#{real_adapter}_connection", config.merge('adapter' => real_adapter))
                      end
        @connected = true
        super(@connection, nil, config)
      end

      def test_select
        @connection.select_all('SELECT  "test_models".* FROM "test_models"  LIMIT 1')
      end

      def visitor
        @connection.visitor
      end

      def visitor=(vis)
        @connection.visitor = vis
      end

      def reconnect!
        @connected = true
      end

      def disconnect!
        @connected = false
      end

      def active?
        @connected
      end
    end
  end
end
