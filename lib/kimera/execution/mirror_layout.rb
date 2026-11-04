# frozen_string_literal: true

require "fileutils"
require_relative "mirror_git"

module Kimera
  module Execution
  end
end

class Kimera::Execution::MirrorLayout
  SKIP = %w[coverage].freeze
  EMPTY = %w[tmp log].freeze
  LINK = %w[vendor node_modules .bundle].freeze
  GIT = ".git"
  HINT =
    "  the mirror copies the project except #{SKIP.join(", ")} " \
      "(#{EMPTY.join(", ")} start empty; #{LINK.join(", ")} are symlinked; " \
      ".git is a private snapshot of the index and refs that reads the project's objects)".freeze

  def initialize(root, registry)
    @given = root
    @registry = registry
  end

  def root = @_root ||= File.expand_path(@given)

  def mutables
    @registry.to_h.keys.map { |f| f.split(File::SEPARATOR).first }.uniq
  end

  def placement(entry)
    return :copy if mutables.include?(entry)
    return :git if entry == GIT
    return :skip if SKIP.include?(entry)
    return :empty if EMPTY.include?(entry)
    LINK.include?(entry) ? :link : :copy
  end

  def populate(mirror)
    Dir.children(root).each { |entry| place(File.join(root, entry), File.join(mirror, entry), entry) }
  end

  def to_s = HINT

  private

  def place(source, target, entry)
    case placement(entry)
    when :copy then FileUtils.cp_r(source, target)
    when :link then File.symlink(source, target)
    when :empty then FileUtils.mkdir_p(target) if File.directory?(source)
    when :git then Kimera::Execution::MirrorGit.new(root).copy(target)
    end
  end
end
