# frozen_string_literal: true

class FakeCopies
  attr_reader :prepared, :adopted

  def initialize(possible: true)
    @possible = possible
    @prepared = []
    @adopted = []
  end

  def possible? = @possible

  def prepare(indexes) = @prepared.push(indexes)

  def adopt(index) = @adopted.push(index)
end

class FakeEngine
  attr_reader :config, :copied, :removed

  def initialize(missing: [], failing: {})
    @missing = missing
    @failing = failing
    @copied = []
    @removed = []
  end

  def new(config) = tap { @config = config }

  def copy(name) = @copied.push(checked(:copy, name))

  def exist?(name) = !@missing.include?(name)

  def remove(name) = @removed.push(checked(:remove, name))

  private

  def checked(action, name)
    failure = @failing[[action, name]]
    raise(failure) if failure
    name
  end
end

class FakeConnections
  attr_reader :released

  def initialize
    @released = 0
  end

  def release! = (@released += 1)
end

class FakeNumbered
  attr_reader :prepared

  def initialize(numbered: true)
    @numbered = numbered
    @prepared = []
  end

  def numbered? = @numbered

  def prepare(index) = @prepared.push(index)
end

class FakeMirror
  attr_reader :prepared

  def initialize
    @prepared = []
  end

  def prepare(slots) = @prepared.push(slots)
end
