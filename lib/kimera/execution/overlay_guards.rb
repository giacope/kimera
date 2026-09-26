# frozen_string_literal: true

require_relative "overlay_guard_modules"

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
      end

      def enum!
        return unless defined?(ActiveRecord::Base)
        ActiveRecord::Base.singleton_class.prepend(OverlayGuardModules.enum)
      end

      def callbacks!
        return unless defined?(ActiveSupport::Callbacks::ClassMethods)
        ActiveSupport::Callbacks::ClassMethods.prepend(OverlayGuardModules.callback)
      end

      def serialize!
        return unless defined?(ActiveRecord::Base)
        ActiveRecord::Base.singleton_class.prepend(OverlayGuardModules.serialization)
      end

      def concern!
        return unless defined?(ActiveSupport::Concern)
        ActiveSupport::Concern.prepend(OverlayGuardModules.concern)
      end

      def serialized?(type)
        OverlayGuardModules.serialized?(type)
      end
    end
  end
end
