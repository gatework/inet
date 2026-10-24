# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"

class InetTest < Minitest::Test
  def test_version_matches_the_package
    spec = Gem::Specification.load(File.expand_path("../inet.gemspec", __dir__))

    assert_equal Inet::VERSION, spec.version.to_s
    assert_match(/\A\d+\.\d+\.\d+\z/, Inet::VERSION)
    assert_equal %w[digest ipaddr json resolv time], spec.runtime_dependencies.map(&:name).sort
  end

  def test_modules_load_independently_without_active_support
    %w[ipaddr ipv6 set domain_name dns_resolver].each do |name|
      code = <<~RUBY
        require "inet/#{name}"
        require "inet"
        require "inet/#{name}"
        abort "ActiveSupport loaded" if defined?(ActiveSupport)
        abort "Algosec namespace leaked" if defined?(Algosec)
      RUBY
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-Ilib", "-e", code)
      assert_predicate status, :success?
      assert_empty stdout
      assert_empty stderr
    end
  end

  def test_require_is_silent_and_repeatable
    code = 'require "inet"; require "inet"; abort unless Inet::VERSION.frozen?'
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-Ilib", "-e", code)

    assert_predicate status, :success?
    assert_empty stdout
    assert_empty stderr
  end
end
