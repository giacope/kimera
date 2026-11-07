# frozen_string_literal: true

require "kimera/scribe"

module FailingScribe
  def failing_scribe(&refusal) = stub_const("Kimera::Scribe", refusing(refusal))

  def refusing(refusal)
    Class.new(Kimera::Scribe) do
      define_method(:initialize) do |node, *place|
        error = refusal.call(node)
        raise(error) if error
        super(node, *place)
      end
    end
  end
end

RSpec.configure { |config| config.include(FailingScribe) }
