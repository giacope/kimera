# frozen_string_literal: true

require "digest"
require "open3"
require_relative "suite_files"

module Kimera
  module Incremental
  end
end

class Kimera::Incremental::Fingerprint
  CONFIG = %w[.rspec .rspec-local Gemfile.lock config/**/* db/schema.rb db/structure.sql].freeze
  SETTINGS = %i[
    framework paths exclude tests exclude_tests exclude_test_names operators require load_path seed isolated
  ].freeze
  RUBY = [RUBY_ENGINE, RUBY_ENGINE_VERSION, RUBY_PLATFORM].join(" ").freeze

  def initialize(root:, options:, sources:)
    @root = root
    @options = options
    @sources = sources
  end

  def to_h
    settings = Digest::SHA256.hexdigest(@options.slice(*SETTINGS).inspect)
    { "commit" => git("rev-parse", "HEAD")&.strip, "ruby" => RUBY, "settings" => settings }
      .merge("files" => digests(suite - @sources), "sources" => digests(@sources))
  end

  private

  def suite
    globs = Kimera::Incremental::SuiteFiles.new(@options[:tests]).globs + CONFIG
    found = Dir.glob(globs, base: @root).uniq.select { |path| File.file?(File.join(@root, path)) }
    found - git("check-ignore", "-z", "--stdin", input: found.join("\0")).to_s.split("\0")
  end

  def git(*, input: "")
    out, status = Open3.capture2("git", "-C", @root, *, stdin_data: input, err: File::NULL)
    out if status.success?
  rescue SystemCallError
    nil
  end

  def digests(paths) = paths.sort.to_h { |path| [path, Digest::SHA256.file(File.join(@root, path)).hexdigest] }
end
