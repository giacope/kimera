# frozen_string_literal: true

require_relative "../error"
require_relative "base"

module Kimera
  module Operators
    class Catalog
      def initialize(defaults, rails)
        @defaults = defaults
        @rails = rails
        @classes = defaults.dup
      end

      def build(keys:)
        requested = expand(keys)
        validate!(requested)
        @classes.map(&:new).select { |operator| requested.include?(operator.key) }
      end

      def keys
        @classes.map { |klass| key_of(klass) }
      end

      def register(*klasses)
        klasses.flatten.each { |klass| admit(klass) }
        self
      end

      def reset!
        @classes.replace(@defaults)
        self
      end

      def custom
        @classes - @defaults
      end

      def expand(keys)
        Array(keys).map(&:to_s).flat_map { |key| expansion(key) }.uniq
      end

      def validate!(requested)
        unknown = requested - keys
        return if unknown.empty?
        raise(UsageError, "unknown operator(s): #{unknown.join(", ")}#{nearest(unknown)} (valid: #{vocabulary})")
      end

      private

      def admit(klass)
        raise(UsageError, "not an operator class: #{klass.inspect}") unless operator?(klass)
        key = key_of(klass)
        taken = @classes.find { |operator| key_of(operator) == key }
        raise(UsageError, "operator key already registered: #{key} (#{taken})") if taken
        @classes << klass
      end

      def key_of(klass) = klass.new.key

      def operator?(klass)
        klass.is_a?(Class) && klass < Base
      end

      def groups
        { "all" => keys, "rails" => @rails, "custom" => custom.map { |klass| key_of(klass) } }
      end

      def expansion(key)
        groups.fetch(key) { [key] }
      end

      def vocabulary
        ["all", "rails", "custom", *keys].join(", ")
      end

      def nearest(unknown)
        checker = DidYouMean::SpellChecker.new(dictionary: [*groups.keys, *keys])
        guesses = unknown.filter_map { |key| checker.correct(key).first }
        "; did you mean #{guesses.join(", ")}?" unless guesses.empty?
      end
    end
  end
end
