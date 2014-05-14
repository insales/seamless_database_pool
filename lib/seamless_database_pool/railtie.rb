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
          original_config = Rails.application.config.database_configuration
          ActiveRecord::Base.configurations = SeamlessDatabasePool.master_database_configuration(original_config)
        end
      end
    end
  end
end
