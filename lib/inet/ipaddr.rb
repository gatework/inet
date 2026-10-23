# frozen_string_literal: true

require "ipaddr"
require_relative "set"

module Inet
  # 在标准 IPAddr 能力上补充防火墙所需的 IPv4 和服务范围运算。
  class IPAddr < ::IPAddr
    IPV4_MAX = ::IPAddr::IN4MASK
    PORT_MAX = (1 << 16) - 1
    SERVICE_MAX = (1 << 24) - 1
    # 服务编码中反复使用的协议号集中命名，避免上层散落裸数字。
    ANY_PROTOCOL = 0
    ICMP = 1
    ICMPV6 = 58
    TCP = 6
    UDP = 17
    PROTOCOL_NUMBERS = { "tcp" => TCP, "udp" => UDP, "icmp" => ICMP, "icmpv6" => ICMPV6,
                         "ms-rpc-tcp" => TCP, "ms-rpc-udp" => UDP }.freeze

    # 规范化 IPv4 输入，并拒绝 IPv6、非法前缀及非十进制设备写法。
    def initialize(address = "0.0.0.0", family = Socket::AF_INET)
      unless [Socket::AF_INET, Socket::AF_UNSPEC].include?(family)
        raise ArgumentError, "Firewall IP helpers require IPv4"
      end

      if address.is_a?(String)
        address = address.sub(%r{\Aany(?=/|\z)}i, "0.0.0.0")
        unless %r{\A[0-9]+(?:\.[0-9]+){3}(?:/(?:[0-9]+|[0-9]+(?:\.[0-9]+){3}))?\z}.match?(address)
          raise ArgumentError, "Invalid IPv4 expression: #{address.inspect}"
        end

        # 设备格式把带前导零的八位组和前缀都按十进制解释。
        address = address.gsub(/\b0+(?=[0-9])/, "")
      elsif !address.is_a?(Integer)
        raise ArgumentError, "IPv4 input must be a string or integer"
      end
      super(address, Socket::AF_INET)
    end

    # 把地址转换成包含首尾整数的标准集合，供范围运算复用。
    def to_set
      raise ArgumentError, "Firewall IP helpers require IPv4" unless ipv4?

      range = to_range
      Set.new(range.begin.to_i..range.end.to_i)
    end

    class << self
      # 接口地址保留主机位；不能直接用 IPAddr.new("host/prefix").to_s。
      def host_cidr(expression, mask = nil)
        host, prefix = string(expression, label: "Interface address").split("/", 2)
        "#{from_i(to_i(host))}/#{prefix_length(mask || prefix || 32)}"
      end

      # 路由目的统一归一化为网络地址和前缀。
      def network_cidr(expression, mask = nil)
        address = new(host_cidr(expression, mask))
        "#{address}/#{address.prefix}"
      end

      # 取接口 CIDR 中的主机地址，供 NAT 出口使用。
      def host(expression) = host_cidr(expression).split("/", 2).first

      # 把不带前缀的 IPv4 文本转换为整数。
      def to_i(address)
        unless address.is_a?(String) && !address.include?("/")
          raise ArgumentError, "Invalid IPv4 address: #{address.inspect}"
        end

        new(address).to_i
      end

      # 把 IPv4 整数转换为点分十进制文本。
      def from_i(number)
        value = integer(number, max: IPV4_MAX, label: "IPv4 integer")
        new(value).to_s
      end

      # 把前缀长度或掩码转换为规范前缀长度。
      def prefix_length(mask)
        mask = integer(mask, max: 32, label: "Prefix length") unless mask.is_a?(String)
        new("0.0.0.0/#{mask}").prefix
      end

      # 根据前缀长度生成点分十进制网络掩码。
      def netmask(mask) = new(IPV4_MAX).mask(prefix_length(mask)).to_s

      # 把通配符掩码转换为网络掩码。
      def wildcard_mask(wildcard)
        unless wildcard.is_a?(String) && /\A[0-9]+(?:\.[0-9]+){3}\z/.match?(wildcard)
          raise ArgumentError, "Invalid IPv4 wildcard"
        end

        (~new(wildcard)).to_s
      end

      # 根据地址和掩码计算覆盖的整数地址集合。
      def subnet(address, mask = 32)
        new(to_i(address)).mask(prefix_length(mask.nil? ? 32 : mask)).to_set
      end

      # 返回子网的网络地址文本。
      def network(address, mask = 32) = from_i(subnet(address, mask).min)

      # 解析主机、CIDR 或网络掩码表达式，也支持两个 IPv4 端点。
      def parse(expression)
        text = string(expression, label: "IPv4 expression")
        parts = text.split("-", -1)
        return between(*parts) if parts.size == 2
        raise ArgumentError, "Invalid IPv4 expression: #{text}" unless parts.size == 1

        new(text).to_set
      end

      # 用两个端点创建有序的闭区间。
      def between(first, last)
        low, high = [to_i(first), to_i(last)].minmax
        Set.new(low..high)
      end

      # 将地址范围精确拆成 CIDR，供持久化与命令生成共用。
      def cidrs(set)
        set.flat_map do |range|
          cursor = range.begin
          last = range.end
          blocks = []
          while cursor <= last
            size = 1
            size *= 2 while (cursor % (size * 2)).zero? && cursor + (size * 2) - 1 <= last
            blocks << [IPAddr.from_i(cursor), 32 - (size.bit_length - 1)]
            cursor += size
          end
          blocks
        end
      end

      # 把整数区间压缩成最短的单个网段或端点表达式。
      def format_range(range)
        unless range.is_a?(Range) && !range.exclude_end? && range.begin.is_a?(Integer) && range.end.is_a?(Integer)
          raise ArgumentError, "IPv4 notation requires a closed integer range"
        end

        integer(range.begin, max: IPV4_MAX, label: "IPv4 lower bound")
        integer(range.end, max: IPV4_MAX, label: "IPv4 upper bound")
        raise ArgumentError, "IPv4 range is reversed" if range.begin > range.end

        size = range.end - range.begin + 1
        first = from_i(range.begin)
        if size.nobits?(size - 1) && (range.begin % size).zero?
          "#{first}/#{32 - (size.bit_length - 1)}"
        else
          "#{first}-#{from_i(range.end)}"
        end
      end

      # 解析单个端口或端口范围，并限制在 16 位端口空间内。
      def ports(expression)
        if expression.is_a?(Range)
          result = Set.new(expression)
          raise ArgumentError, "Port must be in 0..#{PORT_MAX}" if result.max > PORT_MAX

          return result
        end
        text = expression.is_a?(Integer) ? expression.to_s : string(expression, label: "Port")
        match = /\A\s*([0-9]+)(?:(?:\s*-\s*|\s+)([0-9]+))?\s*\z/.match(text)
        raise ArgumentError, "Invalid port expression: #{text}" unless match

        first, last = [match[1], match[2] || match[1]].map do |endpoint|
          integer(endpoint, max: PORT_MAX, label: "Port")
        end.minmax
        Set.new(first..last)
      end

      # 把协议名称或编号转换成服务编码使用的协议编号。
      def protocol_number(protocol)
        protocol = protocol.to_s if protocol.is_a?(Integer) || protocol.is_a?(Symbol)
        name = string(protocol, label: "Protocol").downcase
        return ANY_PROTOCOL if name == "any"

        PROTOCOL_NUMBERS.fetch(name) { integer(name, max: 255, label: "Protocol number") }
      end

      # 两种 ICMP 都以消息类型和代码匹配，不把类型限制当作普通目的端口。
      def icmp?(protocol) = [ICMP, ICMPV6].include?(protocol_number(protocol))

      # 服务编码的高八位保存协议，低十六位保存目标端口；省略端口时使用零。
      def service(expression)
        text = string(expression, label: "Service expression")
        protocol, port, *unexpected_parts = text.split("/", -1)
        raise ArgumentError, "Invalid service expression: #{text}" unless protocol && unexpected_parts.empty?

        ranges = ports(port || 0)
        return Set.new(0..SERVICE_MAX) if protocol.casecmp?(ANY_PROTOCOL.to_s) || protocol.casecmp?("any")

        base = protocol_number(protocol) << 16
        Set.new(*ranges.map { |range| (base + range.begin)..(base + range.end) })
      end

      private

      # 校验并转换整数输入，同时限制其数值范围。
      def integer(value, max:, label:)
        unless value.is_a?(Integer) || (value.is_a?(String) && /\A[0-9]+\z/.match?(value))
          raise ArgumentError, "#{label} must be an integer in 0..#{max}"
        end

        number = value.is_a?(Integer) ? value : Integer(value, 10)
        raise ArgumentError, "#{label} must be in 0..#{max}" unless number.between?(0, max)

        number
      end

      # 校验文本输入并保留原字符串，便于上层继续解析原始表达式。
      def string(value, label:)
        raise ArgumentError, "#{label} must be a string" unless value.is_a?(String)

        value
      end
    end
  end
end
