# frozen_string_literal: true

class Kimera::GuardProbe
  def initialize(node, ids)
    @node = node
    @ids = ids
  end

  def edits = placed(registered)

  def watch = placed("")

  private

  def placed(tail)
    finish = @node.location.end_offset
    return [[finish, finish, tail], [head, head, "; #{probe.join("; ")}"]] unless @node.equal_loc
    start = @node.body.location.start_offset
    [[start, start, "(#{probe.join("; ")}; "], [finish, finish, ")#{tail}"]]
  end

  def head = (@node.rparen_loc || @node.parameters&.location || @node.name_loc).end_offset

  def probe = @ids.map { |id| "::Kimera::RUNTIME.active?(#{Integer(id)})" }

  def registered = @ids.map { |id| "; ::Kimera::RUNTIME.privatize(#{Integer(id)}, self, :#{@node.name})" }.join
end
