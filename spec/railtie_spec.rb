# frozen_string_literal: true

require 'spec_helper'

require 'rails'
require 'active_record/railtie'
require 'seamless_database_pool/railtie'

class DummyApp < Rails::Application
end

RSpec.describe SeamlessDatabasePool::Railtie do
  it "installs log subscriber" do
    described_class.initializers.each(&:run)
    # expect ?
  end


  it "installs rake task" do
    require 'rake'
    require 'rake/testtask'

    Rails.application.load_tasks
    expect(Rake.application["db:load_config"].actions.map(&:source_location).map(&:first)).to include(/seamless_database_pool/)

    ActiveRecord::Tasks::DatabaseTasks.database_configuration = {}
    Rake.application["db:load_config"].invoke
    ActiveRecord::Base.configurations
  end
end
