# frozen_string_literal: true

require 'rubygems'

if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start do
    add_filter 'spec'
  end
end

require 'active_record'
if defined?(ActiveRecord::VERSION)
  puts "Testing Against ActiveRecord #{ActiveRecord::VERSION::STRING} on Ruby #{RUBY_VERSION}"
end

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'seamless_database_pool'))
require File.expand_path(File.join(File.dirname(__FILE__), 'test_model'))

$LOAD_PATH << File.expand_path('test_adapter', __dir__)

RSpec.configure do |config|
  config.run_all_when_everything_filtered = true
  config.filter_run :focus

  # Run specs in random order to surface order dependencies. If you find an
  # order dependency and want to debug it, you can fix the order by providing
  # the seed, which is printed after each run.
  #     --seed 1234
  config.order = 'random'
  config.expect_with(:rspec) { |c| c.syntax = %i[should expect] }
  config.mock_with(:rspec) { |c| c.syntax = %i[should expect] }
end

# enable ruby 2.7 warnings
if defined?(Warning) && Warning.respond_to?(:[]=)
  $VERBOSE = true
  Warning[:deprecated] = true
end
