# frozen_string_literal: true

require_relative "callback"
require_relative "reflections"
require_relative "concern_overrides"

module Kimera
  module Execution
    CallbackChain =
      Data.define(:chain) do
        def fresh(type, filters)
          running = chain.select { |callback| callback.kind == type }
          filters.reject { |filter| duplicate?(running, filter) }
        end
        private
        def duplicate?(callbacks, filter)
          match = Kimera::Execution::Callback.new(filter)
          callbacks.any? { |callback| match.duplicate?(callback.filter) }
        end
      end

    AttributeType =
      Data.define(:type) do
        def serialized?(depth = 10)
          return false unless depth.positive?
          return true if leaf?
          AttributeType.new(unwrapped).serialized?(depth - 1)
        end
        private
        def leaf?
          defined?(ActiveRecord::Type::Serialized) &&
            type.is_a?(ActiveRecord::Type::Serialized)
        end

        def unwrapped
          type.cast_type
        rescue NoMethodError
          subtype
        end

        def subtype
          type.subtype
        rescue NoMethodError
          nil
        end
      end

    ConcernHook =
      Data.define(:concern, :stored) do
        def replacing?(base)
          Kimera::Execution::OverlayGuards.overlaying? && !base && concern.instance_variable_defined?(stored)
        end

        def chained(trimmed)
          original = concern.instance_variable_get(stored)
          proc do |*words|
            class_exec(*words, &original)
            class_exec(*words, &trimmed)
          end
        end

        def reapply(block)
          ObjectSpace.each_object(Class).each do |klass|
            ConcernOverrides.new(klass, concern).reapply(block) if owner?(klass)
          end
        end
        private
        def owner?(klass)
          return false if klass.singleton_class? || !mixes?(klass)
          [klass.superclass].compact.none? { |parent| mixes?(parent) }
        end

        def mixes?(klass) = GuardModules::MIXES.bind_call(klass, concern)
      end

    module GuardModules
      MIXES = Module.instance_method(:include?)

      ENUMGUARD =
        Module.new do
          def enum(*words, **kwargs, &)
            name = words.find { |a| a.is_a?(Symbol) || a.is_a?(String) } || kwargs.keys.first
            return if name && respond_to?(:defined_enums) && defined_enums.key?(name.to_s)
            super
          end
        end

      CALLBACKGUARD =
        Module.new do
          def set_callback(name, *arguments, &block)
            return super unless Kimera::Execution::OverlayGuards.overlaying?
            type, filters, options = normalize_callback_params(arguments.dup, block)
            fresh = Kimera::Execution::CallbackChain.new(__send__(:get_callbacks, name)).fresh(type, filters)
            return if fresh.empty?
            super(name, type, *fresh, options)
          end
        end

      SERIALIZEGUARD =
        Module.new do
          def serialize(attribute, *words, **options, &)
            return if OverlayGuards.overlaying? && AttributeType.new(type_for_attribute(attribute)).serialized?
            super
          end
        end

      CONCERNGUARD =
        Module.new do
          %i[included prepended].each do |hook|
            stored = :"@_#{hook}_block"
            define_method(hook) do |base = nil, &block|
              concerned = Kimera::Execution::ConcernHook.new(self, stored)
              next super(base, &block) unless block && concerned.replacing?(base)
              instance_variable_set(stored, concerned.chained(block))
              concerned.reapply(block)
            end
          end
        end
    end
  end
end
