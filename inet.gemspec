# frozen_string_literal: true

require_relative "lib/inet/version"

Gem::Specification.new do |spec|
  spec.name = "inet"
  spec.version = Inet::VERSION
  spec.authors = ["inet contributors"]
  spec.summary = "IPv4, IPv6 and immutable interval sets"
  spec.description = "IP address normalization, address ranges, service encoding and immutable integer interval sets."
  spec.homepage = "https://github.com/gatework/inet"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"
  spec.files = Dir.chdir(__dir__) { Dir["lib/**/*.rb", "docs/**/*.md", "README.md", "CHANGELOG.md", "LICENSE"].sort }
  spec.require_paths = ["lib"]
  spec.metadata = {
    "allowed_push_host" => "https://rubygems.org",
    "rubygems_mfa_required" => "true",
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues"
  }
end
