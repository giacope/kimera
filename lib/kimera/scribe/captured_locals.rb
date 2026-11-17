# frozen_string_literal: true

module Kimera
  class Scribe
    class CapturedLocals
      def initialize(original, changed, temporary)
        @original = original
        @changed = changed
        @temporary = temporary
      end

      def node
        wrapped = Scribe.parse("(#{@temporary} = nil; #{assignments}; #{@temporary})").statements.body.first
        body = wrapped.body
        wrapped.copy(body: body.copy(body: body.body.map { |statement| filled(statement) }))
      end

      private

      def assignments
        bindings = @original.targets.map(&:name).zip(@changed.targets.map(&:name))
        bindings.map { |group, name| "#{name} = ($~ && $~[#{group.inspect}])" }.join("; ")
      end

      def filled(statement)
        return statement unless statement.type == :local_variable_write_node && statement.name == @temporary
        statement.copy(value: matched)
      end

      def matched
        call = @changed.call
        call.copy(receiver: Scribe.parse("nil || nil").statements.body.first.copy(right: call.receiver))
      end
    end
  end
end
