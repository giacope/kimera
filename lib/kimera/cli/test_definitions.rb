# frozen_string_literal: true

module Kimera
  class CLI
  end
end

# The files a test glob matches that define a test: a Minitest `def test_…`,
# `define_method("test_…")` or `test "…"`, or a spec example (`it`, `specify`, `it_behaves_like`). A
# glob that matches only a support file (zeitwerk's LoaderTest base class)
# finds no test to run: `init` picks the glob whose files define the most
# tests, and doctor fails one whose files define none.
class Kimera::CLI::TestDefinitions
  DEFINES = /
    (?:^|[{;])\s*(?:(?:def\s+|define_method\(?\s*[:"'])test_|test\s*\(?\s*["']|
    (?:it|specify|example|scenario|it_behaves_like|it_should_behave_like|include_examples)\b)
  /x
  TESTLESS = "Test discovery: %d files match tests:, but none defines a test (`def test_…`, `test \"…\"`, `it`); " \
    "fix tests: in .kimera.yml"
  MISSING = "Test discovery: no test files found; fix tests: in .kimera.yml"

  def self.within(root, glob) = new(Dir.glob(File.join(root, glob)))

  def initialize(files)
    @files = files
  end

  def count = @files.count { |file| defines?(file) }

  def reach = [count, @files.size]

  def discovery
    found = @files.size
    return ["✗", MISSING] if found.zero?
    count.zero? ? ["✗", format(TESTLESS, found)] : ["✓", "Test discovery: #{found} files"]
  end

  private

  def defines?(file)
    File.read(file, encoding: Encoding::UTF_8).scrub.match?(DEFINES)
  rescue SystemCallError
    false
  end
end
