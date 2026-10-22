# frozen_string_literal: true

require "prism"
require_relative "../support/warnings"

Kimera::Warnings::SILENCED.during { require "parser" }

module Kimera
  class Scribe
    class Reading
      VERSION = Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("4.0") ? :Parser40 : :Parser34
      GRAMMAR =
        begin
          Prism::Translation.const_get(VERSION)
        rescue NameError, LoadError => error
          raise(
            LoadError,
            "prism #{Prism::VERSION} is too old for Ruby #{RUBY_VERSION} (#{error.message}); " \
              "run `bundle update --conservative prism` (Ruby 4.0 needs prism >= 1.9)"
          )
        end

      class Builder < Prism::Translation::Parser::Builder
        modernize

        def accessible(node) = node

        def diagnostic(type, reason, *)
          super unless reason == :invalid_encoding
        end
      end

      def initialize(source)
        @source = source
      end

      def tree
        Kimera::Warnings::SILENCED.during do
          parser = GRAMMAR.new(Builder.new)
          parser.diagnostics.all_errors_are_fatal = true
          parser.parse(Parser::Source::Buffer.new("(kimera)", source: @source))
        end
      end
    end
  end
end
