# frozen_string_literal: true

require_relative "../parsing/syntax"

module Kimera
  class Scribe
    module Nodes
      SLASH = %r{(?<!\\)((?:\\\\)*)/}
      DELIMITERS = [%w[/ /], %w[{ }], %w[[ ]], %w[( )], %w[< >], %w[| |], %w[! !]].freeze

      private

      def snippet(source) = Kimera::Syntax.parse(source).value.statements.body.first

      def statements(nodes) = Kimera::Syntax.parse("nil").value.statements.copy(body: nodes)

      def local(name) = Kimera::Syntax.parse("kimera = nil\nkimera").value.statements.body.last.copy(name: name)

      def grouped(nodes) = snippet("(nil)").copy(body: statements(nodes))

      def branched(predicate, truthy, fallback)
        template = snippet("if nil\n  nil\nelse\n  nil\nend")
        otherwise = template.subsequent.copy(statements: statements([fallback].compact))
        template.copy(predicate: predicate, statements: statements([truthy].compact), subsequent: otherwise)
      end

      def pattern(source, options)
        opening, closing = DELIMITERS.find { |pair| pair.none? { |mark| source.include?(mark) } }
        return snippet("/#{source.gsub(SLASH) { "#{::Regexp.last_match(1)}\\/" }}/#{options}") unless opening
        snippet("#{"%r" unless opening == "/"}#{opening}#{source}#{closing}#{options}")
      end

      def flagged(node, flags, **changes)
        node.copy(flags: flags.constants.sum { |name| flag(node, flags, name, changes) })
      end

      def flag(node, flags, name, changes)
        word = name.downcase
        changes.fetch(word) { node.public_send(:"#{word}?") } ? flags.const_get(name) : 0
      end
    end
  end
end
