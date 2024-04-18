# frozen_string_literal: true

source 'https://rubygems.org'

# NB: CI is 'x86_64-linux' platform, need to do `appraisal bundle lock --add-platform x86_64-linux` after regeneration
gemspec

gem 'railties'
gem 'rake'
gem 'simplecov', require: false

gem 'actionpack'
gem 'mysql2'
gem 'pg'
gem 'rspec', ['>= 2.0']
gem 'sqlite3', '~>1.4'

unless defined?(Appraisal)
  gem 'appraisal', require: false
  gem 'pry-byebug'

  group :lint do
    gem 'rubocop'
    gem 'rubocop-rake'
    gem 'rubocop-rspec'
  end
end
