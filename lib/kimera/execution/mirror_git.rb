# frozen_string_literal: true

require "fileutils"
require "open3"

module Kimera
  module Execution
  end
end

class Kimera::Execution::MirrorGit
  OWN = %w[HEAD index].freeze
  SHARED = %w[config packed-refs refs].freeze

  def initialize(root)
    @root = root
  end

  def copy(target)
    own, shared = locations
    return unless shared
    FileUtils.mkdir_p(File.join(target, "objects", "info"))
    OWN.each { |name| take(File.join(own, name), target) }
    SHARED.each { |name| take(File.join(shared, name), target) }
    File.write(File.join(target, "objects", "info", "alternates"), "#{File.join(shared, "objects")}\n")
  end

  private

  def take(source, target)
    FileUtils.cp_r(source, File.join(target, File.basename(source))) if File.exist?(source)
  end

  def locations
    out, = Open3.capture2("git", "rev-parse", "--absolute-git-dir", "--git-common-dir", chdir: @root, err: File::NULL)
    own, shared = out.lines(chomp: true)
    [own, shared && File.expand_path(shared, @root)]
  rescue SystemCallError
    []
  end
end
