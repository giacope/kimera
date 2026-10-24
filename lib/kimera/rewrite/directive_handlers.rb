# frozen_string_literal: true

require_relative "../scribe/nodes"
require_relative "extra_handlers"
require_relative "invocation"
require_relative "pinned_predicate"

module Kimera
  module Rewrite
    module DirectiveHandlers
      CONNECTIVES = { or: ["nil || nil", "nil or nil"], and: ["nil && nil", "nil and nil"] }.freeze
      SPELLED = %w[and or].freeze

      Operation =
        Data.define(:node, :directive) do
          include Kimera::Scribe::Nodes
          def target = directive["to"]&.to_sym

          def swap = node.copy(name: target)

          def retype = node.type == :range_node ? spanned : connected

          def spanned = flagged(node, Kimera::Syntax::RangeFlags, exclude_end: target == :erange)

          def connected
            spelled = SPELLED.include?(node.operator_loc.slice)
            snippet(CONNECTIVES.fetch(target)[spelled ? 1 : 0]).copy(left: node.left, right: node.right)
          end

          def literal = snippet(target.to_s)

          def clear = snippet("()")

          def receiver = node.receiver

          def unlink = node.copy(receiver: node.receiver.receiver)

          def send = flagged(node, Kimera::Syntax::CallNodeFlags, safe_navigation: false)

          def retest = node.copy(predicate: PinnedPredicate.new(node.predicate).to(snippet(target.to_s)))

          def integer = node.copy(value: Integer(directive["value"]))

          def float = node.copy(value: Float(directive["value"]))

          def string = node.copy(unescaped: String(directive["value"]))

          def empty = node.copy(elements: [])

          def drop
            Invocation.new(node).listed { |arguments| arguments.reject.with_index { |_, index| index == position } }
          end

          def nothing = node.copy(arguments: snippet("return nil").arguments)

          def select = node.copy(name: target)

          def remove = node.copy(elements: node.elements.reject.with_index { |_, index| index == position })

          def assign = node.copy(binary_operator: target)

          def keyword = kwargs { |pair| extra.trim(pair) }

          def option = kwargs { |_pair| next }

          def kwargs(&) = Invocation.new(node).rewrite(directive["key"], &)

          def position = Integer(directive[INDEX])

          def fetch = node.copy(name: :fetch)

          def argument = node.arguments.arguments.first

          def symbol = node.copy(unescaped: directive["value"].to_s)

          def default = extra.default

          def regexp = extra.regexp

          def extra = ExtraHandlers::Operation.new(node, directive)
        end
    end
  end
end
