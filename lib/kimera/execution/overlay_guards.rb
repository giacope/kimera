# frozen_string_literal: true

require_relative "guard_modules"

module Kimera
  module Execution
    module OverlayGuards
      class << self
        attr_accessor :overlaying

        alias overlaying? overlaying
      end

      module_function

      def overlay
        install!
        self.overlaying = true
        yield
      ensure
        self.overlaying = false
      end

      def install!
        enum!
        callbacks!
        concern!
        serialize!
        reflections!
      end

      def enum!
        return unless defined?(ActiveRecord::Base)
        ActiveRecord::Base.singleton_class.prepend(GuardModules.enum)
      end

      def callbacks!
        return unless defined?(ActiveSupport::Callbacks::ClassMethods)
        ActiveSupport::Callbacks::ClassMethods.prepend(GuardModules.callback)
      end

      def serialize!
        return unless defined?(ActiveRecord::Base)
        ActiveRecord::Base.singleton_class.prepend(GuardModules.serialization)
      end

      def reflections!
        return unless defined?(ActiveRecord::Reflection)
        ActiveRecord::Reflection.singleton_class.prepend(GuardModules.reflection)
      end

      def concern!
        return unless defined?(ActiveSupport::Concern)
        ActiveSupport::Concern.prepend(GuardModules.concern)
      end

      def serialized?(type)
        GuardModules.serialized?(type)
      end
    end
  end
end
