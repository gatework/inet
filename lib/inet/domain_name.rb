# frozen_string_literal: true

module Inet
  # 域名表达式只支持完整名称或最左侧标签通配，不使用子串匹配。
  module DomainName
    module_function

    def normalize(value)
      name = value.to_s.downcase
      # 一个尾点表示根域；多个尾点是空标签，跨层重复归一化也不能把它变成合法名称。
      name.end_with?("..") ? name : name.delete_suffix(".")
    end

    def exact?(value)
      name = normalize(value)
      name.bytesize <= 253 && name.include?(".") &&
        name.split(".", -1).all? { |label| /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/.match?(label) }
    end

    def wildcard?(value)
      name = normalize(value)
      name.start_with?("*.") && exact?(name.delete_prefix("*."))
    end

    def matches?(expression, domain)
      pattern, name = [expression, domain].map { |value| normalize(value) }
      return false unless exact?(name)

      wildcard?(pattern) ? name.end_with?(pattern.delete_prefix("*")) : exact?(pattern) && pattern == name
    end
  end
end
