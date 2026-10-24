# frozen_string_literal: true

require_relative "test_helper"

class DomainNameTest < Minitest::Test
  def test_normalizes_case_and_one_root_dot_without_repairing_empty_labels
    assert_equal "www.example.test", Inet::DomainName.normalize("WWW.Example.TEST.")
    %w[localhost example..test example.test.. -a.test a-.test a_b.test *.example.test].each do |name|
      refute Inet::DomainName.exact?(name), name
    end
    assert Inet::DomainName.exact?("#{'a' * 63}.test")
    refute Inet::DomainName.exact?("#{'a' * 64}.test")
    assert Inet::DomainName.exact?(["a" * 63, "b" * 63, "c" * 63, "d" * 61].join("."))
    refute Inet::DomainName.exact?(["a" * 63, "b" * 63, "c" * 63, "d" * 62].join("."))
  end

  def test_wildcards_match_only_complete_subdomain_labels
    assert Inet::DomainName.wildcard?("*.EXAMPLE.test.")
    assert Inet::DomainName.matches?("*.example.test", "WWW.Example.test.")
    assert Inet::DomainName.matches?("*.example.test", "a.b.example.test")
    assert Inet::DomainName.matches?("EXAMPLE.test.", "example.test")
    %w[example.test notexample.test example.test.evil *.example.test].each do |name|
      refute Inet::DomainName.matches?("*.example.test", name), name
    end
    refute Inet::DomainName.wildcard?("www.*.example.test")
  end
end
