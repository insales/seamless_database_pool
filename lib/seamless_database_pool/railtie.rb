# frozen_string_literal: true

require 'seamless_database_pool/log_subscriber'

module SeamlessDatabasePool
  # railtie
  class Railtie < ::Rails::Railtie
    initializer 'seamless_database_pool.initialize_logger' do |_app|
      ActiveRecord::LogSubscriber.log_subscribers.each do |subscriber|
        subscriber.extend SeamlessDatabasePool::LogSubscriber
      end
    end

    rake_tasks do
      namespace :db do
        task :load_config do
          # Override seamless_database_pool configuration so db:* rake tasks work as expected.
          ActiveRecord::Base.singleton_class.prepend(SeamlessDatabasePool::ActiveRecordDatabaseConfiguration)
        end
      end
    end
  end
end
