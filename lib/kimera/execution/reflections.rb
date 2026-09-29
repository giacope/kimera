# frozen_string_literal: true

module Kimera
  module Execution
    module Reflections
      module_function

      Declared = Data.define(:key, :reflection, :stale)

      GUARD =
        Module.new do
          def add_reflection(owner, name, reflection)
            before = owner._reflections
            key = Reflections.key(owner, name)
            super
            Reflections.settle(owner, before, Declared.new(key, reflection, before[key])) if OverlayGuards.overlaying?
          end
        end

      def key(owner, name)
        text = name.to_s
        owner._reflections.key?(text) ? text : name.to_sym
      end

      def settle(owner, before, declared)
        return unless declared.stale
        held = owner._reflections
        owner._reflections = before.to_h { |name, _| [name, held[name]] }.merge(held)
        owner.descendants.each { |heir| replace(heir, declared) }
      end

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
