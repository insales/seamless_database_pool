source 'https://rubygems.org'

# NB: CI is 'x86_64-linux' platform, need to do `appraisal bundle lock --add-platform x86_64-linux` after regeneration
gemspec

gem 'railties'
gem 'rake'
gem 'simplecov', require: false

unless defined?(Appraisal)
  gem 'appraisal', require: false
  gem 'pry-byebug'
  gem 'sqlite3', '~>1.4'

  group :lint do
    gem 'rubocop'
  end
end
