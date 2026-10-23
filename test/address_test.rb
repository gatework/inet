# frozen_string_literal: true

require_relative "test_helper"

class AddressTest < Minitest::Test
  def test_helpers_are_available_from_the_entrypoint
    assert Inet.const_defined?(:IPAddr, false)
    assert Inet.const_defined?(:IPv6, false)
    assert Inet.const_defined?(:Set, false)
  end

  def test_ipv4_host_network_and_masks
    ip = Inet::IPAddr
    assert_equal "192.168.1.9/24", ip.host_cidr("192.168.001.009/024")
    assert_equal "192.168.1.0/24", ip.network_cidr("192.168.1.9", "255.255.255.0")
    assert_equal "192.168.1.9", ip.host("192.168.1.9/24")
    assert_equal "255.255.255.0", ip.netmask(24)
    assert_equal "255.255.255.0", ip.wildcard_mask("0.0.0.255")
    assert_equal "192.168.1.0", ip.network("192.168.1.9", 24)
    assert_equal 24, ip.prefix_length("255.255.255.0")
    assert_equal "255.255.255.255", ip.from_i(ip.to_i("255.255.255.255"))
    assert_equal 2**32, ip.parse("any/0").cardinality
    assert_equal ip.parse("192.168.1.0/24"), ip.subnet("192.168.1.9", 24)
    assert_equal ip.parse("0.0.0.0/32"), ip.new.to_set
  end

  def test_ipv4_ranges_and_cidr_decomposition
    ip = Inet::IPAddr
    set = ip.parse("0.0.0.6-0.0.0.1")
    assert_equal [["0.0.0.1", 32], ["0.0.0.2", 31], ["0.0.0.4", 31], ["0.0.0.6", 32]], ip.cidrs(set)
    assert_equal [["0.0.0.0", 0]], ip.cidrs(ip.parse("0.0.0.0/0"))
    assert_equal "0.0.0.0/30", ip.format_range(0..3)
    assert_equal "0.0.0.1-0.0.0.6", ip.format_range(1..6)
    assert_equal set, ip.between("0.0.0.1", "0.0.0.6")
    [nil, "::1", "1.2.3", "1.2.3.256", "1.2.3.4/33", "a-b-c"].each do |value|
      assert_raises(ArgumentError) { ip.parse(value) }
    end
    [-1, 2**32, 1.5, nil].each { |value| assert_raises(ArgumentError) { ip.from_i(value) } }
    [1...3, -1..2, 3..2, 0..(2**32)].each { |value| assert_raises(ArgumentError) { ip.format_range(value) } }
    assert_raises(ArgumentError) { ip.to_i("1.2.3.4/24") }
    assert_raises(ArgumentError) { ip.new("::1", Socket::AF_INET6) }
  end

  def test_ports_and_protocol_service_encoding
    ip = Inet::IPAddr
    ["80-90", "90 80", 80..90, 80...91].each do |value|
      assert_equal Inet::Set.new(80..90), ip.ports(value)
    end
    assert_equal Inet::Set.new(53..53), ip.ports(53)
  end

  def test_protocol_service_encoding
    ip = Inet::IPAddr
    assert_equal 6, ip.protocol_number(:tcp)
    assert_equal 17, ip.protocol_number("MS-RPC-UDP")
    assert_equal 255, ip.protocol_number(255)
    assert ip.icmp?("icmpv6")
    refute ip.icmp?(:tcp)
    assert_equal Inet::Set.new(((6 << 16) | 80)..((6 << 16) | 90)), ip.service("tcp/80-90")
    assert_equal Inet::Set.new(0..((2**24) - 1)), ip.service("any")
    assert_equal Inet::Set.new(0..((2**24) - 1)), ip.service("0/80")
    assert_equal Inet::Set.new((1 << 16)..(1 << 16)), ip.service("icmp")
    ["-1", "65536", -1..1, 0..65_536, nil, "80/90"].each do |value|
      assert_raises(ArgumentError) { ip.ports(value) }
    end
    ["tcp/", "tcp/1/2", "256/80", "unknown/80"].each do |value|
      assert_raises(ArgumentError) { ip.service(value) }
    end
  end

  def test_ipv6_normalization_ranges_and_boundaries
    ip = Inet::IPv6
    assert_equal "2001:db8::/64", ip.canonical("2001:0db8::9/64")
    assert_equal "2001:db8::9/64", ip.canonical("2001:0db8::9/64", host: true)
    assert_equal "::1", ip.canonical("::1")
    assert_predicate ip.address("::1"), :ipv6?
    assert_equal "2001:db8::1-2001:db8::2", ip.normalize("2001:0db8::0001-2001:0db8::0002")
    assert_equal "::/0", ip.normalize("::/0")
    assert_equal 2**128, ip.parse("::/0").cardinality
    assert_equal [["::", "::3"]], ip.ranges(ip.parse("::/126"))
    assert_equal "::", ip.from_i(0)
    assert_equal "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff", ip.from_i((2**128) - 1)
    [1.5, -1, 2**128, "1", nil].each { |value| assert_raises(ArgumentError) { ip.from_i(value) } }
    %i[address canonical parse normalize].each do |method|
      [nil, 1, true, [], "1.2.3.4", " ::1", "fe80::1%eth0"].each do |value|
        assert_raises(ArgumentError) { ip.public_send(method, value) }
      end
    end
    ["::2-::1", "::1/128-::2", "::1-::2-::3"].each do |value|
      assert_raises(ArgumentError) { ip.parse(value) }
    end
  end
end
