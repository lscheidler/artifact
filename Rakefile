require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "yard"
require "yard/rake/yardoc_task.rb"

RSpec::Core::RakeTask.new(:spec)
YARD::Rake::YardocTask.new(:doc)

task :default => :spec
