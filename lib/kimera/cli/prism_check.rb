# frozen_string_literal: true

require "prism"

module Kimera
  class CLI
  end
end

# Kimera::Scribe on Ruby 4.0 parses with Prism::Translation::Parser40, which
# prism ships from 1.9; an older lockfile crashed every command (R3K1).
class Kimera::CLI::PrismCheck
  NEEDED = Gem::Version.new("1.9")
  RUBY = Gem::Version.new("4.0")

  def initialize(version: Prism::VERSION, ruby: RUBY_VERSION)
    @version = version
    @ruby = ruby
  end

  def check
    return ["✓", "Prism: #{@version}"] unless old?
    ["!", "Prism: #{@version} is older than Ruby #{@ruby} needs (1.9); run `bundle update --conservative prism`"]
  end

  private

  def old? = Gem::Version.new(@ruby) >= RUBY && Gem::Version.new(@version) < NEEDED
end
