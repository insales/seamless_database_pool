source 'https://rubygems.org'

# NB: CI is 'x86_64-linux' platform, need to do `appraisal bundle lock --add-platform x86_64-linux` after regeneration
gemspec

gem 'rake'
gem 'simplecov', require: false
gem 'railties'

unless defined?(Appraisal)
  gem 'appraisal', require: false
  gem 'sqlite3', '~>1.4'
  gem 'pry-byebug'

  group :lint do
    gem 'rubocop'
  end
end
