# frozen_string_literal: true

module Kimera
  module Incremental
  end
end

class Kimera::Incremental::SuiteFiles
  FOLDER = %r{\A([^/*?\[\{]+)/}

  def initialize(patterns)
    @patterns = Array(patterns)
  end

  def globs = @patterns + folders.map { |folder| "#{folder}/**/*" }

  def files(root) = globs.flat_map { |glob| Dir.glob(glob, base: root) }

  private

  def folders = @patterns.filter_map { |pattern| pattern[FOLDER, 1] }.uniq
end
