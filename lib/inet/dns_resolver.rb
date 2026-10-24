# frozen_string_literal: true

require "resolv"
require "digest"
require "json"
require "time"
require_relative "ipaddr"
require_relative "domain_name"

module Inet
  # 按调用方上下文和 DNS 视角缓存有期限的证据；不把 DNS 失败解释为空地址。
  class DnsResolver
    FAILURE_TTL = 15
    MAX_CNAME_DEPTH = 8
    attr_reader :context

    def initialize(context: {}, servers: nil, store: nil, clock: -> { Time.now }, transport: nil, dns_class: Resolv::DNS)
      servers = Array(servers)
      raise ArgumentError, "DNS servers must contain at most three IP addresses" if servers.size > 3

      servers.each { |server| ::IPAddr.new(server) }
      @servers = servers.map { |server| server.to_s.dup.freeze }.freeze
      @store = store
      @clock = clock
      @transport = transport
      @dns_class = dns_class
      effective = if @servers.empty?
                    Resolv::DNS::Config.default_config_hash.fetch(:nameserver).map do |server|
                      server.dup.freeze
                    end.freeze
                  else
                    @servers
                  end
      @context = immutable_answer(context.merge("source" => @servers.empty? ? "system" : "device",
                                                "servers" => effective))
      @scope = Digest::SHA256.hexdigest(JSON.generate(@context))
      @answers = {}
    end

    # 同次解析只查一次；跨次操作复用 TTL 内缓存，失败缓存不被视作成功。
    def resolve(domain)
      name = DomainName.normalize(domain)
      key = ["inet", "dns-v1", @scope, name]
      now = @clock.call
      cached = @answers[name] || @store&.read(key)
      return @answers[name] ||= immutable_answer(cached) if cached && Time.iso8601(cached.fetch("expires_at")) > now

      answer = lookup(name, now)
      @store&.write(key, answer, expires_in: [Time.iso8601(answer.fetch("expires_at")) - now, 0].max)
      @answers[name] = answer
    end

    private

    # 缓存编码器不保留冻结状态；复制恢复每层 JSON 值，避免调用方改写 DNS 证据。
    def immutable_answer(value)
      case value
      when Hash then value.to_h { |key, item| [key, immutable_answer(item)] }.freeze
      when Array then value.map { |item| immutable_answer(item) }.freeze
      else value.dup.freeze
      end
    end

    # 仅接受完整域名；通配和单标签主机名不借助本机搜索域猜测。
    def lookup(name, now)
      return record("unsupported", [], FAILURE_TTL, now, "Unsupported domain expression") unless DomainName.exact?(name)

      addresses, ttl = @transport ? @transport.call(name, @servers) : query(name)
      addresses = addresses.map { |ip| Inet::IPAddr.from_i(Inet::IPAddr.to_i(ip)) }.uniq.sort
      return record("unresolved", [], FAILURE_TTL, now, "No A records") if addresses.empty?

      record("resolved", addresses, Integer(ttl), now)
    rescue Resolv::ResolvError, Resolv::ResolvTimeout, IOError, SystemCallError, ArgumentError => error
      record("unresolved", [], FAILURE_TTL, now, error.message)
    end

    # CNAME 与 A 的 TTL 共同决定有效期，限制跳数和每次等待，防止循环和长时间阻塞。
    def query(name)
      servers = context.fetch("servers")
      @dns_class.open(nameserver: servers, search: [], ndots: 1, raise_timeout_errors: true) do |dns|
        dns.timeouts = 1
        visited = []
        ttls = []
        MAX_CNAME_DEPTH.times do
          raise Resolv::ResolvError, "CNAME cycle" if visited.include?(name)

          visited << name
          aliases = dns.getresources("#{name}.", Resolv::DNS::Resource::IN::CNAME)
          if aliases.empty?
            records = dns.getresources("#{name}.", Resolv::DNS::Resource::IN::A)
            ttls.concat(records.map(&:ttl))
            return [records.map { |rr| rr.address.to_s }, ttls.min || 0]
          end
          ttls.concat(aliases.map(&:ttl))
          name = aliases.first.name.to_s.downcase.delete_suffix(".")
        end
        raise Resolv::ResolvError, "CNAME chain exceeds #{MAX_CNAME_DEPTH}"
      end
    end

    # 使用普通 JSON 值保存证据，配置缓存不持有网络连接或解析器对象。
    def record(status, addresses, ttl, now, error = nil)
      { "status" => status, "addresses" => addresses.map(&:freeze).freeze, "resolved_at" => now.iso8601(6).freeze,
        "expires_at" => (now + [ttl, 0].max).iso8601(6).freeze, "source" => context,
        "error" => error&.dup&.freeze }.freeze
    end
  end
end
