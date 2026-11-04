# frozen_string_literal: true

class Kimera::FileSet::Exclusion
  def initialize(patterns)
    @patterns = patterns
  end

  def without(files) = files.reject { |file| globs.any? { |glob| glob.covers?(file) } }

  def unused(files)
    Array(@patterns).reject do |pattern|
      glob = Kimera::FileSet::Glob.new(pattern)
      files.any? { |file| glob.covers?(file) }
    end
  end

  private

  def globs = @_globs ||= Array(@patterns).map { |pattern| Kimera::FileSet::Glob.new(pattern) }
end
