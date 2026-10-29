# frozen_string_literal: true

require_relative "../execution/suite_capture"
require_relative "test_command"

class Kimera::CLI::Instruments
  def initialize(suite: Kimera::Execution::SuiteCapture.new, gems: Gem)
    @suite = suite
    @gems = gems
  end

  def installed?(feature) = @gems.find_files(feature).any?

  def tests(exclusion, files, root) = Kimera::CLI::TestCommand.new(exclusion, files, root: root, suite: @suite)
end
