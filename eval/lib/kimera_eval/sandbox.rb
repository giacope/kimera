# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module KimeraEval
  class Sandbox
    def initialize(dirs = Dir)
      @dirs = dirs
    end

    def root = @_root ||= @dirs.mktmpdir("kimera-eval")

    def copy(source, name = File.basename(source))
      target = File.join(root, "#{name}-#{copies.next}")
      FileUtils.mkdir_p(target)
      FileUtils.cp_r(File.join(source, "."), target)
      target
    end

    def remove! = FileUtils.rm_rf(root)

    private

    def copies = @_copies ||= (1..).each
  end
end
