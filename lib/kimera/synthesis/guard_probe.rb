# frozen_string_literal: true

# A visibility mutant, spliced: a probe at the head of the method's body
# records which tests reach it, and a registration after the definition hides
# the method while the mutant is on. Only a definition that stands as a
# statement can be followed by one.
class Kimera::GuardProbe
  def initialize(node, ids)
    @node = node
    @ids = ids
  end

  def edits
    finish = @node.location.end_offset
    return [[finish, finish, registered], [head, head, "; #{probe.join("; ")}"]] unless @node.equal_loc
    start = @node.body.location.start_offset
    [[start, start, "(#{probe.join("; ")}; "], [finish, finish, ")#{registered}"]]
  end

  private

  def head = (@node.rparen_loc || @node.parameters&.location || @node.name_loc).end_offset

  def probe = @ids.map { |id| "::Kimera::RUNTIME.active?(#{Integer(id)})" }

  def registered = @ids.map { |id| "; ::Kimera::RUNTIME.privatize(#{Integer(id)}, self, :#{@node.name})" }.join
end
