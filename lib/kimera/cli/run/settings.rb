# frozen_string_literal: true

require_relative "../../operators"
require_relative "../../plugins"
require_relative "../../registry/builder"

module Kimera
end

class Kimera::CLI
end

class Kimera::CLI::Run
end

class Kimera::CLI::Run::Settings
  def initialize(values)
    @values = values.freeze
  end

  def [](key) = @values[key]

  def to_h = @values

  def to_hash = @values

  def to_s
    "framework=#{@values[:framework]} jobs=#{@values[:jobs]} sources=#{Array(@values[:paths]).join(",")} " \
      "tests=#{Array(@values[:tests]).join(",")} format=#{@values.fetch(:format, "text")}"
  end

  def plugins = Kimera::Plugins.new(@values[:require], root: @values[:source_root])

  def change(bench) = bench.change(@values[:since], @values[:source_root])

  def scan
    operators = Kimera::Operators.build(keys: @values[:operators])
    Kimera::RegistryScan.new(operators: operators, root: @values[:source_root] || ".", shielded: !@values[:isolated])
  end
end
