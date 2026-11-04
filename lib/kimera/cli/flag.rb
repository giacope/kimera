# frozen_string_literal: true

require "optparse"
require_relative "../error"

module Kimera
  class Flag
    class Assign
      def stored(options, key, value) = options.merge(key => value)

      def to_s = "assign"
    end

    class Collect
      def stored(options, key, value) = options.merge(key => options[key] + [value])

      def to_s = "collect"
    end

    SHARED = {
      config: [["--config FILE", "Load config (default: .kimera.yml)"], :config, Assign.new],
      registry: [["--registry FILE", "Load registry JSON instead of building"], :registry, Assign.new],
      require: [
        ["--require FILE", "Load a Ruby file before scanning, for custom operators (repeatable)"], :require, Collect.new
      ],
      operators: [
        ["--operators a,b,c", Array, "Operator keys, or 'all'/'rails' (default: conservative core)"], :operators,
        Assign.new
      ]
    }.freeze
    private_constant(:SHARED)

    def self.build(switch, key, help, type: nil) = new([*switch, type, help].compact, key, Assign.new)

    def self.repeated(switch, key, help) = new([switch, help], key, Collect.new)

    def self.shared(name) = new(*SHARED.fetch(name))

    def initialize(signature, key, mode)
      @signature = signature
      @key = key
      @mode = mode
    end

    def define(parser, &) = parser.on(*@signature, &)

    def stored(options, value) = @mode.stored(options, @key, value)

    def to_h = { signature: @signature, key: @key, mode: @mode.to_s }

    def ==(other) = other.is_a?(Flag) && other.to_h == to_h
  end

  class FlagTable
    def initialize(banner:, flags:)
      @banner = banner
      @flags = flags
    end

    def parse(argv, defaults)
      options = defaults
      [build { |flag, value| options = flag.stored(options, value) }.parse(argv), options]
    rescue OptionParser::ParseError => error
      raise(UsageError, "#{suggested(error.message)}\nTry: #{command} --help")
    end

    def build
      OptionParser.new do |parser|
        parser.banner = @banner
        @flags.each { |flag| flag.define(parser) { |value| yield(flag, value) } }
      end
    end

    def retitled(banner) = FlagTable.new(banner: banner, flags: @flags)

    def refusal = UsageError.new(@banner)

    def to_a = @flags.dup

    private

    def suggested(message)
      message.sub(/\n\s*Did you mean\?\s+(?<name>\S+).*/m) { "; did you mean --#{Regexp.last_match[:name]}?" }
    end

    def command = @banner.scan(/\AUsage: (kimera(?: [a-z]+)*)/).flatten.fetch(0)
  end
end
