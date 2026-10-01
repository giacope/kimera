# frozen_string_literal: true

require_relative "callback"
require_relative "reflections"
require_relative "concern_overrides"

module Kimera
  module Execution
    module OverlayGuardModules
      module_function

      ENUMGUARD =
        Module.new do
        def enum(*args, **kwargs, &)
          name = args.find { |a| a.is_a?(Symbol) || a.is_a?(String) } || kwargs.keys.first
          return if name && respond_to?(:defined_enums) && defined_enums.key?(name.to_s)
          super
        end
      end

      CALLBACKGUARD =
        Module.new do
        def set_callback(name, *arguments, &block)
          return super unless Kimera::Execution::OverlayGuards.overlaying?
          type, filters, options = normalize_callback_params(arguments.dup, block)
          fresh = Kimera::Execution::OverlayGuardModules.fresh(__send__(:get_callbacks, name), type, filters)
          return if fresh.empty?
          super(name, type, *fresh, options)
        end
      end

      def enum = ENUMGUARD

      def callback = CALLBACKGUARD

      def fresh(chain, type, filters)
        running = chain.select { |callback| callback.kind == type }
        filters.reject { |filter| duplicate?(running, filter) }
      end

      def duplicate?(callbacks, filter)
        match = Kimera::Execution::Callback.new(filter)
        callbacks.any? { |callback| match.duplicate?(callback.filter) }
      end

      SERIALIZEGUARD =
        Module.new do
        def serialize(attribute, *args, **options, &)
          return if OverlayGuards.overlaying? && OverlayGuardModules.serialized?(type_for_attribute(attribute))
          super
        end
      end

      CONCERNGUARD =
        Module.new do
        %i[included prepended].each do |hook|
          stored = :"@_#{hook}_block"
          define_method(hook) do |base = nil, &block|
            next super(base, &block) unless block && OverlayGuardModules.replacing?(self, stored, base)
            instance_variable_set(stored, OverlayGuardModules.chain(instance_variable_get(stored), block))
            OverlayGuardModules.reapply(self, block)
          end
        end
      end

      def serialization = SERIALIZEGUARD

      def reflection = Reflections::GUARD

      MIXES = Module.instance_method(:include?)

      def concern = CONCERNGUARD

      def reapply(concern, block)
        ObjectSpace.each_object(Class).each do |klass|
          ConcernOverrides.reapply(klass, concern, block) if owner?(klass, concern)
        end
      end

      def owner?(klass, concern)
        return false if klass.singleton_class? || !mixes?(klass, concern)
        [klass.superclass].compact.none? { |parent| mixes?(parent, concern) }
      end

      def mixes?(klass, concern) = MIXES.bind_call(klass, concern)

      def chain(original, trimmed)
        proc do |*args|
          class_exec(*args, &original)
          class_exec(*args, &trimmed)
        end
      end

      def replacing?(target, stored, base)
        Kimera::Execution::OverlayGuards.overlaying? && !base && target.instance_variable_defined?(stored)
      end

      def serialized?(type, depth = 10)
        return false unless depth.positive?
        return true if leaf?(type)
        serialized?(unwrap(type), depth - 1)
      end

      def leaf?(type)
        defined?(ActiveRecord::Type::Serialized) &&
          type.is_a?(ActiveRecord::Type::Serialized)
      end

      def unwrap(type)
        type.cast_type
      rescue NoMethodError
        subtype(type)
      end

      def subtype(type)
        type.subtype
      rescue NoMethodError
        nil
      end
    end
  end
end
