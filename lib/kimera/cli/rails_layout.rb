# frozen_string_literal: true

module Kimera
  class CLI
  end
end

# Whether a project is a Rails application, or a Rails engine with a dummy
# app: an engine is any lib/**/*.rb (a bounded scan) that subclasses
# Rails::Engine or calls isolate_namespace, not only lib/**/engine.rb.
class Kimera::CLI::RailsLayout
  DUMMIES = %w[spec/dummy test/dummy].freeze
  ENGINE = /<\s*(?:::)?Rails::Engine\b|^\s*isolate_namespace\b/
  SCANNED = 2_000

  def initialize(root)
    @root = root
  end

  def rails? = application? || engine?

  def application? = File.file?(File.join(@root, "config", "application.rb"))

  def engine? = dummy? && Dir.glob(File.join(@root, "lib", "**", "*.rb")).first(SCANNED).any? { engine_class?(it) }

  private

  def dummy? = DUMMIES.any? { File.file?(File.join(@root, it, "config", "application.rb")) }

  def engine_class?(path) = File.read(path, encoding: Encoding::UTF_8).scrub.match?(ENGINE)
end
