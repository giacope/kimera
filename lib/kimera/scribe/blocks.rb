# frozen_string_literal: true

module Kimera
  class Scribe
    class Block < Form
      TYPES = %i[block numblock itblock].freeze
      CLAUSED = %i[rescue ensure].freeze

      def text
        body = children[2]
        opening, ending = CLAUSED.include?(body&.type) ? [" do", "end"] : [" {", "}"]
        "#{head}#{opening}#{bars}#{clauses(body, @pen.with(children.first(2)))}#{closing(ending)}"
      end

      private

      def call = children.first

      def parameters
        given = children[1]
        given.is_a?(Parser::AST::Node) ? given : @node.updated(:args, [])
      end

      def head
        kind = call.type
        return "->#{"(#{Parameters.new(parameters, @pen).text})" if parameters.children.any?}" if kind == :lambda
        %i[send csend].include?(kind) ? Call.new(call, @pen).regular : part(0, Level::PRIMARY)
      end

      def bars = call.type == :lambda || parameters.children.empty? ? "" : " |#{Parameters.new(parameters, @pen).bars}|"
    end

    class Parameters < Form
      TYPES = %i[args].freeze

      def text = joined(items(plain))

      def bars = joined(plain.size == 1 && plain.first.type == :arg ? "#{items(plain)}," : items(plain))

      private

      def plain = children.reject { |child| child.type == :shadowarg }

      def joined(own)
        shadows = children.select { |child| child.type == :shadowarg }
        shadows.empty? ? own : "#{own}; #{shadows.map { |shadow| shadow.children.first }.join(", ")}"
      end

      def items(nodes) = nodes.map { |node| pens.fetch(children.index(node)).write(node) }.join(", ")
    end

    class Parameter < Form
      TYPES = %i[arg optarg restarg kwarg kwoptarg kwrestarg blockarg shadowarg].freeze
      PREFIXES = { restarg: "*", kwrestarg: "**", blockarg: "&" }.freeze
      SUFFIXES = { optarg: " = ", kwoptarg: ": ", kwarg: ":" }.freeze

      def text = "#{PREFIXES[@node.type]}#{children.first}#{SUFFIXES[@node.type]}#{default if children[1]}"

      private

      def default = @pen.with([@node.updated(nil, children.first(1))]).write(children[1], Level::ASSIGNMENT)
    end

    class Nesting < Form
      TYPES = %i[mlhs].freeze

      def text = enclosed(Parameters)
    end

    class Destructuring < Form
      TYPES = %i[procarg0].freeze

      def text
        inner = Parameters.new(@node, @pen).text
        children.size > 1 || Hash(@node.location&.to_hash)[:begin] ? "(#{inner})" : inner
      end
    end
  end
end
