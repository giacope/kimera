# frozen_string_literal: true

module Kimera
  class Scribe
    class Place
      class Kept
        LOOSE = %i[
          statements_node arguments_node parameters_node block_parameters_node embedded_statements_node
          embedded_variable_node else_node when_node in_node rescue_node ensure_node implicit_node implicit_rest_node
          keyword_hash_node multi_target_node numbered_parameters_node it_parameters_node
        ].freeze
        OPENED = %i[
          string_node symbol_node x_string_node interpolated_string_node interpolated_symbol_node array_node
        ].freeze
        CLOSED = {
          unless_node: :end_keyword_loc, while_node: :closing_loc, until_node: :closing_loc,
          defined_node: :lparen_loc
        }.freeze
        BARE = %i[yield_node super_node call_node].freeze
        COMMAND = /\A[a-z_]/i

        def initialize(node, root, ends)
          @node = node
          @root = root
          @ends = ends
        end

        def slices = visited(@node).last.to_h.compare_by_identity

        private

        def visited(node)
          inner = node.compact_child_nodes.map { |child| visited(child) }
          heredoc = inner.any?(&:first) || laid?(node)
          kept = inner.flat_map(&:last)
          [heredoc, heredoc || !standalone?(node) ? kept : [[node, node.slice], *kept]]
        end

        def written?(node)
          start = node.location.start_offset - @root.location.start_offset
          !start.negative? && @root.slice.byteslice(start, node.location.length) == node.slice
        end

        def laid?(node) = node.respond_to?(:heredoc?) && node.heredoc? && node.location.start_line < @ends

        def standalone?(node)
          type = node.type
          return false if LOOSE.include?(type) || type.end_with?("_target_node") || !written?(node)
          opened?(node, type) && closed?(node, type) && !commanded?(node, type)
        end

        def opened?(node, type) = !OPENED.include?(type) || !node.opening_loc.nil?

        def closed?(node, type)
          return !node.public_send(CLOSED.fetch(type)).nil? if CLOSED.key?(type)
          type != :if_node || node.if_keyword_loc.nil? || !node.end_keyword_loc.nil?
        end

        def commanded?(node, type)
          return false unless BARE.include?(type)
          parenthesised = type == :call_node ? node.opening_loc : node.lparen_loc
          node.arguments && !parenthesised && (type != :call_node || node.name.match?(COMMAND))
        end
      end
    end
  end
end
