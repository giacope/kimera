# frozen_string_literal: true

module Kimera
  module Incremental
  end
end

# The globs a test suite reads: its test patterns, and everything under each
# pattern's fixed top folder (spec/, test/), where its helpers, support files
# and fixtures live. An absolute pattern or one that starts with a glob has no
# such folder.
class Kimera::Incremental::SuiteFiles
  FOLDER = %r{\A([^/*?\[\{]+)/}

  def initialize(patterns)
    @patterns = Array(patterns)
  end

  def globs = @patterns + folders.map { |folder| "#{folder}/**/*" }

  private

  def folders = @patterns.filter_map { |pattern| pattern[FOLDER, 1] }.uniq
end
