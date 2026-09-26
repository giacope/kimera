# frozen_string_literal: true

module Kimera
  module Execution
    module Reflections
      module_function

      GUARD =
        Module.new do
          def add_reflection(owner, name, reflection)
            key = Reflections.key(owner, name)
            stale = OverlayGuards.overlaying? && owner._reflections[key]
            super
            Reflections.inherit(owner, key, stale, reflection) if stale
          end
        end

      def key(owner, name)
        text = name.to_s
        owner._reflections.key?(text) ? text : name.to_sym
      end

      def inherit(owner, key, stale, reflection)
        owner.descendants.each { |heir| replace(heir, key, stale, reflection) }
      end

      def replace(heir, key, stale, reflection)
        held = heir._reflections
        return unless held[key].equal?(stale)
        heir.clear_reflections_cache
        heir._reflections = held.merge(key => reflection)
      end
    end
  end
end
