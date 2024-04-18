Gem::Specification.new do |spec|
  spec.name          = 'seamless_database_pool'
  spec.version       = File.read(File.expand_path('VERSION', __dir__)).chomp
  spec.authors       = ['Brian Durand']
  spec.email         = ['bbdurand@gmail.com']
  spec.description   = 'Add support for master/slave database database clusters in ActiveRecord to improve performance.'
  spec.summary       = 'Add support for master/slave database clusters in ActiveRecord to improve performance.'
  spec.homepage      = 'https://github.com/bdurand/seamless_database_pool'
  spec.license       = 'MIT'

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']
  spec.required_ruby_version = '>= 3.0'

  spec.add_runtime_dependency('activerecord', ['>= 6.1'])
  spec.add_runtime_dependency('concurrent-ruby', ['~> 1.0'])

  spec.add_development_dependency('actionpack', ['>= 3.2.0'])
  spec.add_development_dependency('mysql2', ['>= 0'])
  spec.add_development_dependency('pg', ['>= 0'])
  spec.add_development_dependency('rspec', ['>= 2.0'])
  spec.add_development_dependency('sqlite3', ['>= 0'])
end
