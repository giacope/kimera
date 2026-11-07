# frozen_string_literal: true

require_relative "../../execution/harness"
require_relative "../../frameworks/name_exclusion"
require_relative "../../frameworks/suite"
require_relative "../../incremental/selection"
require_relative "null_selection"

class Kimera::CLI::Run::Bench
  def initialize(
    suites: Kimera::Frameworks::SuiteRegistry.new, harnesses: Kimera::Execution::Harness, diffs: Kimera::Incremental::Selection
  )
    @suites = suites
    @harnesses = harnesses
    @diffs = diffs
  end

  def change(since, root)
    since ? @diffs.from_diff(since: since, root: root) : Kimera::CLI::Run::NullSelection.new
  end

  def suite(framework, names)
    loaded = @suites.load(framework)
    names.empty? ? loaded : Kimera::Frameworks::NameExclusion.new(loaded, names)
  end

  def harness(**) = @harnesses.build(**)
end
