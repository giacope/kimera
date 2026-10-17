# frozen_string_literal: true

module Kimera
  module Operators
    class RegexpTokens
      Token = Data.define(:kind, :offset, :text)

      ANCHORS = { "\\A" => true, "\\z" => true, "\\Z" => true, "^" => true, "$" => true }.freeze
      REPEATS = %w[* + ?].freeze
      BOUNDED = /\G\{(\d*)(,?)(\d*)\}[?+]?/
      MODIFIED = /\G[*+?][?+]?/
      NAMED = /\G\\[pPkgu][{<']/
      CLOSERS = { "{" => "}", "<" => ">", "'" => "'" }.freeze
      NESTING = { "[" => 1, "]" => -1 }.freeze
      GROUP = /\G\(\?(?:<[=!]|[:=!>~]|<[^>]*>|'[^']*'|[imx-]*[:)]|\#[^)]*\))/

      def initialize(source)
        @source = source
      end

      def tokens
        @_tokens ||= scan
      end

      private

      def scan
        found = []
        at = 0
        repeatable = false
        while @source[at]
          at, repeatable, token = step(at, repeatable)
          found << token if token
        end
        found
      end

      def step(at, repeatable)
        char = @source[at]
        return escape(at) if char == "\\"
        return [class_end(at + 1), true] if char == "["
        return [group(at), false] if char == "("
        return anchor(at, char) if ANCHORS.key?(char)
        return repeat(at) if repeatable && quantifier?(at)
        [at + 1, true]
      end

      def escape(at)
        pair = @source[at, 2]
        return anchor(at, pair) if ANCHORS.key?(pair)
        named = @source.match(NAMED, at)
        return [@source.index(CLOSERS.fetch(named[0][-1]), named.end(0)).to_i + 1, true] if named
        [at + 2, true]
      end

      def anchor(at, text) = take(Token.new(:anchor, at, text))

      def take(token) = [token.offset + token.text.length, false, token]

      def quantifier?(at) = REPEATS.include?(@source[at]) || (@source.match?(BOUNDED, at) && bounded?(at))

      def bounded?(at)
        lower, _comma, upper = @source.match(BOUNDED, at).captures
        !(lower.empty? && upper.empty?)
      end

      def repeat(at)
        take(Token.new(:quantifier, at, (@source.match(BOUNDED, at) || @source.match(MODIFIED, at))[0]))
      end

      def group(at)
        opener = @source.match(GROUP, at)
        opener ? opener.end(0) : at + 1
      end

      def class_end(at)
        at = opening(at)
        depth = 1
        at, depth = nested(at, depth) while depth.positive? && @source[at]
        at
      end

      def opening(at)
        at += 1 if @source[at] == "^"
        @source[at] == "]" ? at + 1 : at
      end

      def nested(at, depth)
        char = @source[at]
        return [at + 2, depth] if char == "\\"
        [at + 1, depth + NESTING.fetch(char, 0)]
      end
    end
  end
end
