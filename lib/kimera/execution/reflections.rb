# frozen_string_literal: true

module Kimera
  module Execution
    class Reflections
      class Declared
        def initialize(key, reflection, stale)
          @key = key
          @reflection = reflection
          @stale = stale
        end

        def stale? = !@stale.nil?

        def pass_down(heir)
          held = heir._reflections
          return unless held[@key].equal?(@stale)
          heir.clear_reflections_cache
          heir._reflections = held.merge(@key => @reflection)
        end
      end

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
        return unless declared.stale?
        held = @owner._reflections
        @owner._reflections = before.to_h { |name, _| [name, held[name]] }.merge(held)
        @owner.descendants.each { |heir| declared.pass_down(heir) }
      end
    end
  end
end
