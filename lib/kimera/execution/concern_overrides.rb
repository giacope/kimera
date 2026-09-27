# frozen_string_literal: true

require "prism"

module Kimera
  module Execution
    module ConcernOverrides
      module_function

      MACROS = %i[scope has_many has_one belongs_to has_and_belongs_to_many].freeze

      GUARD =
        Module.new do
          MACROS.each do |macro|
            define_method(macro) do |name = nil, *args, **options, &block|
              return if ConcernOverrides.skipping?(self, name)
              super(name, *args, **options, &block)
            end
          end
        end

      def reapply(klass, concern, block)
        klass.singleton_class.prepend(GUARD)
        skipping(klass, declared(klass, concern)) { klass.class_eval(&block) }
      end

      def skipping(klass, names, thread = Thread.current)
        previous = thread[:kimera_concern_overrides]
        thread[:kimera_concern_overrides] = [klass, names]
        yield
      ensure
        thread[:kimera_concern_overrides] = previous
      end

      def skipping?(klass, name)
        held, names = Thread.current[:kimera_concern_overrides]
        held.equal?(klass) && names.include?(name.to_s)
      end

      def declared(klass, concern)
        after(calls(Prism.parse_file(source(klass)).value), concern.name.split("::").last)
      rescue StandardError
        []
      end

      def source(klass) = Object.const_source_location(klass.name).first

      def after(calls, tail)
        calls.drop_while { |call| !mixin?(call, tail) }.drop(1).filter_map { |call| declaration(call) }
      end

      def mixin?(call, tail)
        %i[include prepend].include?(call.name) &&
          (call.arguments&.arguments || []).any? { |arg| arg.slice.split("::").last == tail }
      end

      def declaration(call)
        first = call.arguments&.arguments&.first
        first.unescaped if MACROS.include?(call.name) && first.is_a?(Prism::SymbolNode)
      end

      def calls(node, found = [])
        found << node if node.is_a?(Prism::CallNode)
        node.compact_child_nodes.each { |child| calls(child, found) }
        found
      end
    end
  end
end
