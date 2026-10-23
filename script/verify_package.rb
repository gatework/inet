# frozen_string_literal: true

require "bundler"
require "open3"
require "rbconfig"
require "rubygems/package"
require "tmpdir"

module PackageVerification
  ROOT = File.expand_path("..", __dir__)
  ATTRIBUTES = %i[name version platform dependencies metadata required_ruby_version licenses
                  authors summary description homepage require_paths executables extensions].freeze

  def self.verify(artifact)
    spec = Gem::Specification.load(File.join(ROOT, "inet.gemspec"))
    package = Gem::Package.new(File.expand_path(artifact))
    unless ATTRIBUTES.all? { |key| package.spec.public_send(key) == spec.public_send(key) }
      raise "Package metadata differs from inet.gemspec"
    end
    unless package.contents.sort == spec.files.sort && package.spec.files.sort == spec.files.sort
      raise "Package file list differs from inet.gemspec"
    end

    Dir.mktmpdir("inet-package-") do |directory|
      package.extract_files(File.join(directory, "contents"))
      spec.files.each do |path|
        unless File.binread(File.join(ROOT, path)) == File.binread(File.join(directory, "contents", path))
          raise "Package content differs from source: #{path}"
        end
      end
      install_and_load(File.expand_path(artifact), spec.version.to_s, directory)
    end
    puts "Package metadata, contents, isolated installation and require passed."
  end

  def self.install_and_load(artifact, version, directory)
    gem_directory = File.join(directory, "gems")
    Bundler.with_unbundled_env do
      env = { "GEM_HOME" => gem_directory, "GEM_PATH" => gem_directory, "RUBYOPT" => nil,
              "RUBYLIB" => nil, "RUBYGEMS_GEMDEPS" => nil }
      run(env, directory, "-S", "gem", "install", "--local", "--no-document", artifact)
      code = <<~RUBY
        require "inet"
        abort "version mismatch" unless Inet::VERSION == ARGV.fetch(0)
        abort "IPv4 helpers missing" unless Inet::IPAddr.network_cidr("192.0.2.9/24") == "192.0.2.0/24"
        abort "IPv6 helpers missing" unless Inet::IPv6.parse("::/0").cardinality == 2**128
        abort "Set operations missing" unless (Inet::Set.new(1..5) - Inet::Set.new(2..4)).ranges == [1..1, 5..5]
        installed = Gem.loaded_specs.fetch("inet").full_gem_path
        abort "loaded source checkout" unless File.realpath(installed).start_with?(File.realpath(ENV.fetch("GEM_HOME")) + "/")
      RUBY
      run(env, directory, "-e", code, version)
    end
  end

  def self.run(env, directory, *)
    output, status = Open3.capture2e(env, RbConfig.ruby, *, chdir: directory)
    raise "Isolated package check failed: #{output}" unless status.success?
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Usage: bundle exec ruby script/verify_package.rb PATH.gem" unless ARGV.size == 1
  PackageVerification.verify(ARGV.fetch(0))
end
