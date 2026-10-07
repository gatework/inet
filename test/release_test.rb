# frozen_string_literal: true

require_relative "test_helper"
require_relative "../script/release"

class ReleaseTest < Minitest::Test
  def metadata
    { "name" => "inet", "version" => "0.1.0", "platform" => "ruby", "yanked" => false, "sha" => "same" }
  end

  def decide(value = nil, tag: nil, head: "current", ref: "branch", checksum: "same")
    Release.decision(value, tag_commit: tag, head: head, ref_type: ref, version: "0.1.0", checksum: checksum)
  end

  def test_new_version_is_published
    assert_equal :push, decide
  end

  def test_same_version_on_a_later_commit_is_skipped
    assert_equal :skip, decide(metadata, tag: "previous", checksum: "new-package")
  end

  def test_rerun_after_accepted_upload_only_verifies
    assert_equal :published, decide(metadata)
    assert_equal :published, decide(metadata, tag: "current")
  end

  def test_conflicting_artifact_is_rejected
    assert_raises(Release::Error) { decide(metadata, checksum: "different") }
  end

  def test_unpublished_tag_on_another_commit_is_rejected
    assert_raises(Release::Error) { decide(tag: "previous") }
  end

  def test_tag_trigger_cannot_skip_a_conflicting_commit
    assert_raises(Release::Error) { decide(metadata, tag: "previous", ref: "tag") }
  end

  def test_yanked_or_wrong_registry_identity_is_rejected
    [{ "yanked" => true }, { "name" => "other" }, { "version" => "0.2.0" }, { "platform" => "java" }].each do |change|
      assert_raises(Release::Error) { decide(metadata.merge(change), tag: "previous") }
    end
  end

  def test_unknown_upload_outcome_is_not_replayed
    release = Release.allocate
    release.instance_variable_set(:@artifact, "candidate.gem")
    attempts = []
    uploader = lambda do |*arguments|
      attempts << arguments
      false
    end

    release.stub(:system, uploader) do
      release.stub(:verify_remote!, -> { raise Release::Error, "unconfirmed" }) do
        capture_io { assert_raises(Release::Error) { release.send(:publish, :push) } }
      end
    end

    assert_equal 1, attempts.size
    assert_includes attempts.first, "candidate.gem"
    assert_equal Release::HOST, attempts.first.last
  end

  def test_already_published_artifact_does_not_upload
    release = Release.allocate
    release.instance_variable_set(:@spec, Gem::Specification.load("inet.gemspec"))
    release.stub(:system, ->(*) { flunk "must not upload again" }) do
      release.stub(:verify_remote!, true) { capture_io { release.send(:publish, :published) } }
    end
  end

  def test_retrying_an_old_release_cannot_replace_latest
    refute Release.latest?(%w[v0.1.0 v0.2.0], "0.1.0")
  end

  def test_latest_release_uses_numeric_versions
    assert Release.latest?(%w[v0.9.0 v0.10.0], "0.10.0")
    assert Release.latest?([], "0.1.0")
  end

  def test_release_notes_preserve_first_item_without_a_blank_line
    release = Release.allocate
    release.instance_variable_set(:@spec, Gem::Specification.load("inet.gemspec"))
    text = "# Changes\n\n## 0.1.0\n- First change.\n- Second change.\n\n## 0.0.1\n- Previous.\n"

    File.stub(:read, text) do
      assert_equal "- First change.\n- Second change.", release.send(:release_notes)
    end
  end
end
