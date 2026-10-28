# frozen_string_literal: true

require "optparse"
require_relative "../error"

module Kimera
  Flag =
    Data.define(:switch, :key, :help, :type, :collect) do
      def self.build(switch, key, help, **settings)
        new(switch: switch, key: key, help: help, type: nil, collect: false, **settings)
      end

      def self.shared(name, **settings) = new(**self::SHARED.fetch(name), **settings)

      def define(parser, &) = parser.on(*signature, &)

      def stored(options, value) = options.merge(key => collect ? options[key] + [value] : value)
      private
      def signature = [*switch, type, help].compact
    end

  Flag::SHARED = {
    force: { switch: "--force", key: :force, help: "Replace an existing file", type: nil, collect: false },
    config: {
      switch: "--config FILE", key: :config, help: "Load config (default: .kimera.yml)", type: nil, collect: false
    },
    registry: {
      switch: "--registry FILE", key: :registry, help: "Load registry JSON instead of building", type: nil,
      collect: false
    },
    require: {
      switch: "--require FILE", key: :require,
      help: "Load a Ruby file before scanning, for custom operators (repeatable)", type: nil, collect: true
    },
    operators: {
      switch: "--operators a,b,c", key: :operators,
      help: "Operator keys, or 'all'/'rails' (default: conservative core)", type: Array, collect: false
    }
  }.freeze

  FlagTable =
    Data.define(:banner, :flags) do
      def parse(argv, defaults)
        options = defaults
        [build { |flag, value| options = flag.stored(options, value) }.parse(argv), options]
      rescue OptionParser::ParseError => error
        raise(UsageError, "#{suggested(error.message)}\nTry: #{command} --help")
      end

      def suggested(message)
        message.sub(/\n\s*Did you mean\?\s+(?<name>\S+).*/m) { "; did you mean --#{Regexp.last_match[:name]}?" }
      end

      def command = banner[/\AUsage: (kimera(?: [a-z]+)*)/, 1]

      def build
        OptionParser.new do |parser|
          parser.banner = banner
          flags.each { |flag| flag.define(parser) { |value| yield(flag, value) } }
        end
      end

      def keys = flags.map(&:key)
    end
end
