# frozen_string_literal: true

require "digest"
require "json"
require "net/http"
require "open3"
require_relative "verify_package"

# 发布只接受当前提交对应的 CI 构件；上传结果不明时只重试读取。
class Release
  HOST = "https://rubygems.org"
  class Error < StandardError; end

  def initialize(artifact)
    @artifact = File.expand_path(artifact)
    @spec = Gem::Specification.load(File.join(PackageVerification::ROOT, "inet.gemspec"))
    @checksum = Digest::SHA256.file(@artifact).hexdigest
  end

  def run(command)
    raise Error, "Expected prepare or publish" unless %w[prepare publish].include?(command)

    PackageVerification.verify(@artifact)
    validate_context!
    decision = self.class.decision(metadata, tag_commit: tag_commit, head: git("rev-parse", "HEAD").strip,
                                             ref_type: ENV.fetch("GITHUB_REF_TYPE"), version: @spec.version.to_s,
                                             checksum: @checksum)
    if command == "prepare"
      File.write("pkg/release-notes.md", release_notes)
      File.open(ENV.fetch("GITHUB_OUTPUT"), "a") do |file|
        file.puts "release_needed=#{decision != :skip}"
        file.puts "tag=v#{@spec.version}"
        file.puts "artifact=#{@spec.file_name}"
      end
      puts "Release decision: #{decision} (#{@spec.full_name}, SHA256 #{@checksum})"
    elsif decision != :skip
      publish(decision)
    end
  end

  def self.decision(metadata, tag_commit:, head:, ref_type:, version:, checksum:)
    if metadata && (metadata.values_at("name", "version", "platform", "yanked") != ["inet", version, "ruby", false])
      raise Error, "RubyGems returned a different or yanked version"
    end

    if tag_commit && tag_commit != head
      return :skip if ref_type == "branch" && metadata

      raise Error, "Release tag points to another commit"
    end
    return :push unless metadata
    raise Error, "Published version has different bytes; bump Inet::VERSION" unless metadata.fetch("sha") == checksum

    :published
  end

  def self.latest?(tags, version)
    versions = tags.grep(/\Av\d+\.\d+\.\d+\z/).map { |tag| Gem::Version.new(tag.delete_prefix("v")) }
    versions.all? { |published| Gem::Version.new(version) >= published }
  end

  private

  def validate_context!
    raise Error, "Release must run in gatework/inet Actions" unless ENV["GITHUB_ACTIONS"] == "true" &&
                                                                    ENV["GITHUB_REPOSITORY"] == "gatework/inet"
    raise Error, "Release version must be X.Y.Z" unless @spec.version.to_s.match?(/\A\d+\.\d+\.\d+\z/)
    unless git("rev-parse", "HEAD").strip == ENV["GITHUB_SHA"]
      raise Error, "Checkout differs from the triggering commit"
    end

    raise Error, "Checkout has uncommitted files" unless git("status", "--porcelain", "-uall").empty?
    raise Error, "Release requires main" unless ENV.values_at("GITHUB_REF_TYPE", "GITHUB_REF_NAME") == %w[branch main]

    git("merge-base", "--is-ancestor", "HEAD", "origin/main")
    release_notes
  end

  def release_notes
    heading = /^## #{Regexp.escape(@spec.version.to_s)}(?:[ \t][^\n]*)?$/
    changelog = File.read("CHANGELOG.md")
    raise Error, "CHANGELOG.md needs a section for #{@spec.version}" unless changelog.match?(heading)

    notes = changelog.split(heading, 2).last.split(/^## /, 2).first.strip
    raise Error, "Release notes are empty" if notes.empty?

    notes
  end

  def git(*arguments)
    output, error, status = Open3.capture3("git", *arguments)
    raise Error, "git #{arguments.join(' ')}: #{error.strip}" unless status.success?

    output
  end

  def tag_commit
    tags = git("tag", "--list", "v#{@spec.version}").strip
    git("rev-parse", "#{tags}^{commit}").strip unless tags.empty?
  end

  def request(path)
    uri = URI("#{HOST}#{path}")
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) do |http|
      http.get(uri.request_uri)
    end
  end

  def metadata
    response = request("/api/v2/rubygems/inet/versions/#{@spec.version}.json")
    return if response.is_a?(Net::HTTPNotFound)
    raise Error, "RubyGems lookup returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    value = JSON.parse(response.body)
    raise Error, "RubyGems returned invalid metadata" unless value.is_a?(Hash)

    value
  end

  def publish(decision)
    if decision == :push
      # 不自动重放上传；即使连接中断，服务端也可能已经接受这个版本。
      accepted = system(RbConfig.ruby, "-S", "gem", "push", @artifact, "--host", HOST)
      puts "Upload command succeeded: #{accepted == true}; verifying registry and download."
    end
    verify_remote!
    puts "Published and verified #{HOST}/gems/inet/versions/#{@spec.version}"
  end

  def verify_remote!
    12.times do |attempt|
      begin
        value = metadata
        if value
          self.class.decision(value, tag_commit: nil, head: nil, ref_type: "tag",
                                     version: @spec.version.to_s, checksum: @checksum)
          response = request("/downloads/#{@spec.file_name}")
          return true if response.is_a?(Net::HTTPSuccess) && Digest::SHA256.hexdigest(response.body) == @checksum
        end
      rescue IOError, SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError => error
        warn "RubyGems readback pending: #{error.class}"
      end
      sleep 5 if attempt < 11
    end
    raise Error, "Upload outcome is unconfirmed. Check RubyGems SHA256 #{@checksum} before retrying this job."
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Usage: bundle exec ruby script/release.rb prepare|publish PATH.gem" unless ARGV.size == 2
  begin
    Release.new(ARGV.fetch(1)).run(ARGV.fetch(0))
  rescue Release::Error => error
    abort "release: #{error.message}"
  end
end
