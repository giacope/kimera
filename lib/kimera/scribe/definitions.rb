# frozen_string_literal: true

module Kimera
  class Scribe
    class Definition < Form
      TYPES = %i[def defs].freeze
      SIMPLE = %i[self lvar ivar gvar cvar const].freeze

      def text
        *owner, name, parameters, body = children
        "def #{receiver(owner)}#{name}#{signature(parameters)}#{clauses(body, @pen.scoped([parameters]))}#{closing}"
      end

      def level = Level::KEYWORD

      private

      def receiver(owner)
        return "" if owner.empty?
        definer = owner.first
        bare = SIMPLE.include?(definer.type) || definer == @node.updated(:send, [nil, definer.children[1]])
        bare ? "#{part(0, Level::PRIMARY)}." : "(#{part(0)})."
      end

      def signature(parameters) = parameters.children.empty? ? "" : "(#{Parameters.new(parameters, @pen.scoped).text})"
    end

    class Namespace < Form
      TYPES = %i[class sclass module].freeze

      def text = "#{opening}#{parent}#{clauses(children.last, @pen.scoped)}#{closing}"

      def level = Level::KEYWORD

      private

      def opening = type == :sclass ? "class << #{part(0, Level::PRIMARY)}" : "#{type} #{part(0, Level::PRIMARY)}"

      def parent = type == :class && children[1] ? " < #{part(1, Level::PRIMARY)}" : ""
    end
  end
end
