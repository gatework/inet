# frozen_string_literal: true

require "ipaddr"
require_relative "set"

module Inet
  # IPv6 范围独立于 IPv4；JSON 端点使用地址文本，避免客户端整数精度丢失。
  module IPv6
    module_function

    def address(value)
      validate_text!(value)
      result = ::IPAddr.new(value)
      raise ArgumentError, "Expected IPv6" unless result.ipv6?

      result
    end

    def canonical(value, host: false)
      ip = address(value)
      return "#{address(value.split('/').first)}/#{ip.prefix}" if host

      value.include?("/") ? "#{ip}/#{ip.prefix}" : ip.to_s
    end

    def parse(value)
      validate_text!(value)
      if value.include?("-")
        parts = value.split("-", -1)
        unless parts.size == 2 && parts.none? { |part| part.include?("/") }
          raise ArgumentError, "IPv6 range needs two hosts"
        end

        first, last = parts.map { |part| address(part).to_i }
        Set.new(first..last)
      else
        ip = address(value)
        Set.new(ip.to_range.begin.to_i..ip.to_range.end.to_i)
      end
    end

    def normalize(value)
      validate_text!(value)
      return canonical(value) unless value.include?("-")

      range = parse(value).ranges.first
      "#{from_i(range.begin)}-#{from_i(range.end)}"
    end

    def from_i(value)
      unless value.is_a?(Integer) && value.between?(0, ::IPAddr::IN6MASK)
        raise ArgumentError, "IPv6 integer must be in 0..#{::IPAddr::IN6MASK}"
      end

      ::IPAddr.new(value, Socket::AF_INET6).to_s
    end

    def ranges(set) = set.map { |range| [from_i(range.begin), from_i(range.end)] }

    def validate_text!(value)
      return if value.is_a?(String) && value == value.strip && !value.include?("%")

      raise ArgumentError, "Invalid IPv6 address"
    end
    private_class_method :validate_text!
  end
end
