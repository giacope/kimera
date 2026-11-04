# frozen_string_literal: true

require "kimera/scribe"

# Kimera's writer, failing the way it can, in place of the real one for an
# example: built for a node, it raises what the block answers for that node,
# and is the real writer when the block answers nil.
module FailingScribe
  def failing_scribe(&refusal) = stub_const("Kimera::Scribe", refusing(refusal))

  # A writer that raises what +refusal+ answers for the node it is built for.
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
