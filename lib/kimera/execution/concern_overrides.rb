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
        names = declared(klass, concern)
        return klass.class_eval(&block) if names.empty?
        klass.singleton_class.prepend(GUARD)
        skipping(klass, names) { klass.class_eval(&block) }
      end

      def skipping(klass, names)
        previous = Thread.current[:kimera_concern_overrides]
        Thread.current[:kimera_concern_overrides] = [klass, names]
        yield
      ensure
        Thread.current[:kimera_concern_overrides] = previous
      end

      def skipping?(klass, name)
        held, names = Thread.current[:kimera_concern_overrides]
        held.equal?(klass) && names.include?(name.to_s)
      end

      def declared(klass, concern)
        file = source(klass)
        return [] unless file && concern.name
        after(calls(Prism.parse_file(file).value), concern.name.split("::").last)
      rescue StandardError
        []
      end

      def source(klass)
        klass.name && Object.const_source_location(klass.name)&.first
      rescue NameError
        nil
      end

      def after(calls, tail)
        mark = calls.find { |call| mixin?(call, tail) }
        return [] unless mark
        calls.filter_map { |call| declaration(call) if call.location.start_offset > mark.location.start_offset }
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
        found << node if node.is_a?(Prism::CallNode) && node.receiver.nil?
        node.compact_child_nodes.each { |child| calls(child, found) }
        found
      end
    end
  end
end
