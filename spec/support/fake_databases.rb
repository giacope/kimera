# frozen_string_literal: true

# The copies of the test database the parent makes for each process, as
# Kimera::Execution::DatabaseCopies makes them: possible or not, and writing
# down the processes it prepared and the one that adopted its copy.
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

# A copy engine (PostgreSQL's or SQLite's), standing in for its class too:
# DatabaseCopies builds it from the connection's configuration. It copies,
# finds and removes the databases it is told, raising for the names given in
# +failing+, and writes down each.
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

# The parent's connections to the test database, as ParentConnections lets
# go of them before a fork: it counts how often.
class FakeConnections
  attr_reader :released

  def initialize
    @released = 0
  end

  def release! = (@released += 1)
end

# Test databases named by TEST_ENV_NUMBER, as NumberedDatabases prepares one
# per worker: numbered or not, writing down each worker it prepared.
class FakeNumbered
  attr_reader :prepared

  def initialize(numbered: true)
    @numbered = numbered
    @prepared = []
  end

  def numbered? = @numbered

  def prepare(index) = @prepared.push(index)
end

# The database of the mirrors past the first, as MirrorDatabase has the
# parent copy it: writing down the slots it prepared.
class FakeMirror
  attr_reader :prepared

  def initialize
    @prepared = []
  end

  def prepare(slots) = @prepared.push(slots)
end
