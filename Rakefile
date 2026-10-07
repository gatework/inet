# frozen_string_literal: true

require "rake/testtask"
require "rubocop/rake_task"
require "rubygems/package"

Rake::TestTask.new(:test) do |task|
  task.libs << "test"
  task.pattern = "test/**/*_test.rb"
end

RuboCop::RakeTask.new(:lint)

desc "Build the gem into pkg/"
task :build do
  spec = Gem::Specification.load("inet.gemspec")
  mkdir_p "pkg"
  Gem::Package.build(spec, false, false, File.join("pkg", spec.file_name))
end

desc "Build and verify an isolated gem installation"
task package: :build do
  spec = Gem::Specification.load("inet.gemspec")
  ruby "script/verify_package.rb", File.join("pkg", spec.file_name)
end

desc "Run all local and CI checks"
task ci: %i[test lint package]
task default: :ci
