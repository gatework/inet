# frozen_string_literal: true

require_relative "test_helper"

class DnsResolverTest < Minitest::Test
  class Cache
    def initialize = @entries = {}
    def read(key) = @entries[key]
    def write(key, value, **_options) = @entries[key] = Marshal.load(Marshal.dump(value))
  end

  def test_default_clock_and_context_work_without_active_support
    resolver = Inet::DnsResolver.new(servers: ["192.0.2.53"], transport: ->(*) { [["192.0.2.1"], 60] })
    answer = resolver.resolve("example.test")
    assert_equal "resolved", answer.fetch("status")
    assert_in_delta Time.now.to_f, Time.iso8601(answer.fetch("resolved_at")).to_f, 2
    refute answer.fetch("source").key?("device_id")
  end

  def test_context_is_copied_and_frozen_before_evidence_is_cached
    tenant = +"tenant-a"
    context = { "tenant" => tenant }
    resolver = Inet::DnsResolver.new(context: context, servers: ["192.0.2.53"],
                                     transport: ->(*) { [["192.0.2.1"], 60] })
    tenant.replace("tenant-b")
    context["extra"] = true
    answer = resolver.resolve("example.test")
    assert_equal "tenant-a", answer.fetch("source").fetch("tenant")
    refute answer.fetch("source").key?("extra")
    assert_raises(FrozenError) { answer.fetch("source").fetch("tenant").replace("changed") }
  end

  def test_cname_ttl_limits_a_records_and_cycles_or_missing_answers_stay_unknown
    cname = Struct.new(:name, :ttl)
    address = Struct.new(:address, :ttl)
    records = {
      ["alias.test.", Resolv::DNS::Resource::IN::CNAME] => [cname.new("target.test", 20)],
      ["target.test.",
       Resolv::DNS::Resource::IN::A] => [address.new("192.0.2.2", 60), address.new("192.0.2.1", 120)],
      ["cycle.test.", Resolv::DNS::Resource::IN::CNAME] => [cname.new("cycle.test", 60)]
    }
    fake = Object.new
    fake.define_singleton_method(:timeouts=) { |value| value }
    fake.define_singleton_method(:getresources) { |name, type| records.fetch([name, type], []) }
    now = Time.utc(2026, 9, 16, 12)
    client = Object.new
    client.define_singleton_method(:open) { |**_options, &block| block.call(fake) }
    resolver = Inet::DnsResolver.new(context: { "device_id" => 1 }, servers: ["192.0.2.53"], clock: lambda {
      now
    }, dns_class: client)
    answer = resolver.resolve("ALIAS.test.")
    assert_equal ["192.0.2.1", "192.0.2.2"], answer.fetch("addresses")
    assert_equal now + 20, Time.iso8601(answer.fetch("expires_at"))
    assert_equal "unresolved", resolver.resolve("cycle.test").fetch("status")
    assert_equal "unresolved", resolver.resolve("missing.test").fetch("status")
    assert_equal "unsupported", resolver.resolve("*.example.test").fetch("status")
  end

  def test_cache_partitions_devices_and_resolver_views_and_failures_are_retried_after_a_short_ttl
    now = Time.utc(2026, 9, 16, 12)
    store = Cache.new
    calls = 0
    transport = lambda { |_name, _servers|
      calls += 1
      raise Resolv::ResolvTimeout, "timeout"
    }
    options = { store: store, clock: -> { now }, transport: transport }
    make = ->(id, servers) { Inet::DnsResolver.new(context: { "device_id" => id }, servers: servers, **options) }
    first = make.call(1, ["192.0.2.53"])
    first.resolve("example.test")
    first.resolve("EXAMPLE.test.")
    make.call(1, ["192.0.2.53"]).resolve("example.test")
    assert_equal 1, calls
    make.call(2, ["192.0.2.53"]).resolve("example.test")
    make.call(1, ["198.51.100.53"]).resolve("example.test")
    assert_equal 3, calls
    now += 16
    make.call(1, ["192.0.2.53"]).resolve("example.test")
    assert_equal 4, calls
    system = make.call(1, [])
    assert_equal "system", system.context.fetch("source")
  end

  def test_repeated_normalization_never_promotes_empty_terminal_labels_to_an_exact_domain
    calls = []
    resolver = Inet::DnsResolver.new(context: { "device_id" => 1 }, servers: ["192.0.2.53"],
                                     transport: lambda { |name, _servers|
                                       calls << name
                                       [["192.0.2.1"], 60]
                                     })

    ["example.test..", "example.test..."].each do |name|
      assert_equal "unsupported", resolver.resolve(name).fetch("status")
      refute Inet::DomainName.matches?("example.test", name)
      refute Inet::DomainName.matches?("*.example.test..", "www.example.test")
    end
    assert_empty calls
    assert_equal "resolved", resolver.resolve("EXAMPLE.test.").fetch("status")
    assert_equal ["example.test"], calls
  end
end
