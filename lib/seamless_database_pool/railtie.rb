require 'seamless_database_pool/log_subscriber'

module SeamlessDatabasePool
  class Railtie < ::Rails::Railtie
    initializer 'seamless_database_pool.initialize_logger' do |app|
      ActiveRecord::LogSubscriber.log_subscribers.each do |subscriber|
        subscriber.extend SeamlessDatabasePool::LogSubscriber
      end
    end

    rake_tasks do
      namespace :db do
        task :load_config do
          # Override seamless_database_pool configuration so db:* rake tasks work as expected.
          module DatabaseConfiguration
            def configurations
              if Rails::VERSION::MAJOR >= 6
                # Rails 6 (and above) compatible behaviour
                ActiveRecord::DatabaseConfigurations.new(
                  SeamlessDatabasePool.master_database_configuration(super.deep_dup)
                )
              else
                # Before Rails 6 compatible behaviour
                SeamlessDatabasePool.master_database_configuration(super.deep_dup)
              end
            end
          end
          ActiveRecord::Base.singleton_class.prepend(DatabaseConfiguration)
        end
      end
    end
  end
end
