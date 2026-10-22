# frozen_string_literal: true

require_relative "../runtime"
require_relative "guard_modules"

module Kimera
  module Execution
    class OverlayGuards
      HOOKS = [
        ["ActiveRecord::Base", :singleton_class, GuardModules::ENUMGUARD],
        ["ActiveSupport::Callbacks::ClassMethods", :itself, GuardModules::CALLBACKGUARD],
        ["ActiveSupport::Concern", :itself, GuardModules::CONCERNGUARD],
        ["ActiveRecord::Base", :singleton_class, GuardModules::SERIALIZEGUARD],
        ["ActiveRecord::Reflection", :singleton_class, Reflections::GUARD]
      ].freeze

      def initialize(hooks = HOOKS)
        @hooks = hooks
      end

      def overlay(&)
        install!
        Kimera::RUNTIME.overlay(&)
      end

      def install!
        @hooks.each do |path, side, guard|
          Object.const_get(path).public_send(side).prepend(guard) if Object.const_defined?(path)
        end
      end
    end
  end
end
