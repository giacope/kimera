# frozen_string_literal: true

require_relative "../error"
require_relative "base"

module Kimera
  module Operators
    class Catalog
      class Roster
        def initialize(defaults)
          @defaults = defaults
          @classes = defaults.dup
        end

        def register(*klasses)
          klasses.flatten.each { |klass| admit(klass) }
          self
        end

        def reset!
          @classes.replace(@defaults)
          self
        end

        def custom = @classes - @defaults

        def each(&) = @classes.each(&)

        private

        def admit(klass)
          raise(UsageError, "not an operator class: #{klass.inspect}") unless operator?(klass)
          key = klass.new.key
          taken = @classes.find { |operator| operator.new.key == key }
          raise(UsageError, "operator key already registered: #{key} (#{taken})") if taken
          @classes << klass
        end

        def operator?(klass)
          klass.is_a?(Class) && klass < Base
        end
      end

      def initialize(roster, rails)
        @roster = roster
        @rails = rails
      end

      def build(keys:)
        requested = expand(keys)
        validate!(requested)
        @roster.each.map(&:new).select { |operator| requested.include?(operator.key) }
      end

      def keys
        @roster.each.map { |klass| key_of(klass) }
      end

      def validate!(requested)
        unknown = requested - keys
        return if unknown.empty?
        raise(UsageError, "unknown operator(s): #{unknown.join(", ")}#{nearest(unknown)} (valid: #{vocabulary})")
      end

      def expand(keys)
        Array(keys).map(&:to_s).flat_map { |key| expansion(key) }.uniq
      end

      private

      def key_of(klass) = klass.new.key

      def groups
        { "all" => keys, "rails" => @rails, "custom" => @roster.custom.map { |klass| key_of(klass) } }
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
        return "" if guesses.empty?
        "; did you mean #{guesses.join(", ")}?"
      end
    end
  end
end
