# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::Bundle
  RELATIVE = %r{\bpath:?\s*\(?\s*["'](?!/|~)}
  REMOTES = /^PATH\n  remote: (.+)$/
  GEMFILE = "Gemfile"

  def initialize(root, env = ENV)
    @root = root
    @env = env
  end

  def gemfile(mirror)
    copy = File.join(mirror, named)
    return unless File.file?(copy)
    own = File.join(home, named)
    File.file?(own) && outward?(own) ? own : copy
  end

  private

  def named
    given = File.expand_path(@env.fetch("BUNDLE_GEMFILE", GEMFILE), home)
    given.start_with?("#{home}/") ? given.delete_prefix("#{home}/") : GEMFILE
  end

  def outward?(gemfile)
    lock = "#{gemfile}.lock"
    return read(gemfile).match?(RELATIVE) unless File.file?(lock)
    base = File.dirname(gemfile)
    read(lock).scan(REMOTES).flatten.any? { |remote| escapes?(remote, base) }
  end

  def escapes?(remote, base)
    path = File.expand_path(remote, base)
    !remote.start_with?("/") && path != home && !path.start_with?("#{home}/")
  end

  def home = @_home ||= File.expand_path(@root)

  def read(path) = File.read(path, encoding: Encoding::UTF_8).scrub
end
