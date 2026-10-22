# frozen_string_literal: true

require_relative "../rewrite/ast_walk"
require_relative "guardrail_factories"

class Kimera::SpliceReopening
  include Kimera::GuardrailFactories

  Assignment =
    Data.define(:node) do
      def edit = [node.location.start_offset, value.block.location.start_offset, header]

      def header
        owner = base
        "#{constant} = (#{owner}.const_defined?(:#{name}, false) ? #{owner}.const_get(:#{name}) : " \
          "#{factory}); #{constant}.class_eval "
      end
      private
      def value = node.value

      def path? = node.type == :constant_path_write_node

      def name = path? ? node.target.name : node.name

      def constant = path? ? node.target.slice : node.name_loc.slice

      def factory
        start = value.location.start_offset
        value.location.slice.byteslice(0, value.block.location.start_offset - start).rstrip
      end

      def base
        return LEXICAL unless path?
        node.target.parent&.slice || "::Object"
      end
    end

  def initialize(map)
    @map = map
  end

  def edits = constants.map(&:edit)

  private

  def constants
    found = []
    Kimera::Rewrite::AstWalk.new(@map.ast).visit { |node| found << Assignment.new(node) if reopenable?(node) }
    found
  end
end
