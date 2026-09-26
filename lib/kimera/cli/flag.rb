# frozen_string_literal: true

require "optparse"
require_relative "../error"

module Kimera
  Flag =
    Data.define(:switch, :key, :help, :type, :collect) do
      def self.build(switch, key, help, type: nil, collect: false)
        new(switch: switch, key: key, help: help, type: type, collect: collect)
      end

      def define(parser, options)
        parser.on(*signature) { |value| store(options, value) }
      end
      private
      def signature = [*switch, type, help].compact

      def store(options, value)
        collect ? options[key] << value : options[key] = value
      end
    end

  FlagTable =
    Data.define(:banner, :flags) do
      def parse(argv, options)
        build(options).parse(argv)
      rescue OptionParser::ParseError => error
        raise(UsageError, "#{error.message}\n#{banner}")
      end

      def build(options)
        OptionParser.new do |parser|
          parser.banner = banner
          flags.each { |flag| flag.define(parser, options) }
        end
      end

      def keys = flags.map(&:key)
    end

  FORCE_FLAG = Flag.build("--force", :force, "Replace an existing file")
  CONFIG_FLAG = Flag.build("--config FILE", :config, "Load config (default: .kimera.yml)")
  REGISTRY_FLAG = Flag.build("--registry FILE", :registry, "Load registry JSON instead of building")
  REQUIRE_FLAG = Flag.build(
    "--require FILE", :require,
    "Load a Ruby file before scanning, for custom operators (repeatable)",
    collect: true
  )
  OPERATORS_FLAG = Flag.build(
    "--operators a,b,c", :operators,
    "Operator keys, or 'all'/'rails' (default: conservative core)",
    type: Array
  )
end
