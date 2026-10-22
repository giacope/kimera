# frozen_string_literal: true

require_relative "../parsing/syntax"

module Kimera
  module Execution
    class ConcernOverrides
      MACROS = %i[scope has_many has_one belongs_to has_and_belongs_to_many].freeze
      SLOT = :kimera_concern_overrides

      Skipping =
        Data.define(:klass) do
          def include?(name)
            held, names = Thread.current[SLOT]
            held.equal?(klass) && names.include?(name.to_s)
          end
        end

      GUARD =
        Module.new do
          MACROS.each do |macro|
            define_method(macro) do |name = nil, *words, **options, &block|
              return if Skipping.new(self).include?(name)
              super(name, *words, **options, &block)
            end
          end
        end

      def initialize(klass, concern)
        @klass = klass
        @concern = concern
      end

      def reapply(block)
        @klass.singleton_class.prepend(GUARD)
        skipping(declared) { @klass.class_eval(&block) }
      end

      private

      def skipping(names)
        thread = Thread.current
        previous = thread[SLOT]
        thread[SLOT] = [@klass, names]
        yield
      ensure
        thread[SLOT] = previous
      end

      def declared
        tree = Kimera::Syntax.parse(File.read(source, encoding: Encoding::UTF_8), filepath: source)
        after(calls(tree.value), @concern.name.split("::").last)
      rescue StandardError
        []
      end

      def source = Object.const_source_location(@klass.name).first

      def after(calls, tail)
        calls.drop_while { |call| !mixin?(call, tail) }.drop(1).filter_map { |call| declaration(call) }
      end

      def mixin?(call, tail)
        %i[include prepend].include?(call.name) &&
          (call.arguments&.arguments || []).any? { |argument| argument.slice.split("::").last == tail }
      end

      def declaration(call)
        first = call.arguments&.arguments&.first
        first.unescaped if MACROS.include?(call.name) && first.is_a?(Prism::SymbolNode)
      end

      def calls(node)
        (node.is_a?(Prism::CallNode) ? [node] : []) + node.compact_child_nodes.flat_map { |child| calls(child) }
      end
    end
  end
end
