# frozen_string_literal: true

module Kimera
  module Execution
    class Reflections
      Declared = Data.define(:key, :reflection, :stale)

      GUARD =
        Module.new do
          def add_reflection(owner, name, reflection)
            before = owner._reflections
            table = Reflections.new(owner)
            key = table.key(name)
            super
            table.settle(before, Declared.new(key, reflection, before[key])) if Kimera::RUNTIME.overlaying?
          end
        end

      def initialize(owner)
        @owner = owner
      end

      def key(name)
        text = name.to_s
        @owner._reflections.key?(text) ? text : name.to_sym
      end

      def settle(before, declared)
        return unless declared.stale
        held = @owner._reflections
        @owner._reflections = before.to_h { |name, _| [name, held[name]] }.merge(held)
        @owner.descendants.each { |heir| replace(heir, declared) }
      end

      private

      def replace(heir, declared)
        held = heir._reflections
        key = declared.key
        return unless held[key].equal?(declared.stale)
        heir.clear_reflections_cache
        heir._reflections = held.merge(key => declared.reflection)
      end
    end
  end
end
