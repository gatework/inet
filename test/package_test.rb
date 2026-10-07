# frozen_string_literal: true

require_relative "test_helper"
require_relative "../script/verify_package"
require "fileutils"

class PackageTest < Minitest::Test
  def build_candidate
    Dir.mktmpdir("inet-test-") do |directory|
      spec = Gem::Specification.load("inet.gemspec").dup
      artifact = File.join(directory, "candidate.gem")
      yield spec, artifact
    end
  end

  def test_missing_runtime_file_is_rejected
    build_candidate do |spec, artifact|
      spec.files -= ["lib/inet/version.rb"]
      capture_io { Gem::Package.build(spec, false, false, artifact) }

      error = assert_raises(RuntimeError) { PackageVerification.verify(artifact) }
      assert_match(/file list/, error.message)
    end
  end

  def test_changed_package_bytes_are_rejected
    build_candidate do |spec, artifact|
      source = File.join(File.dirname(artifact), "source")
      spec.files.each do |path|
        target = File.join(source, path)
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp(path, target)
      end
      File.write(File.join(source, "lib/inet.rb"), "raise 'unexpected package content'\n")
      capture_io { Dir.chdir(source) { Gem::Package.build(spec, false, false, artifact) } }

      error = assert_raises(RuntimeError) { PackageVerification.verify(artifact) }
      assert_match(/content differs/, error.message)
    end
  end
end
