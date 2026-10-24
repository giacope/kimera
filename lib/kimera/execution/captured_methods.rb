# frozen_string_literal: true

require_relative "redefinition"

# A Method or UnboundMethod the suite took at load (`REGISTERED =
# method(:to_int)`) keeps the definition it was taken from. Once kimera's
# overlay redefines that method, the two are no longer ==, and calling the
# captured one runs the code as it was loaded, so a test comparing them fails
# under kimera only. Ruby cannot make them equal; this names them, and the
# files to leave out, for the message that stops the run.
class Kimera::Execution::CapturedMethods
  LOOKUP = Module.instance_method(:instance_method)
  KINDS = [Method, UnboundMethod].freeze
  SHOWN = 3

  def initialize(root)
    @root = root
  end

  def cause
    found = stale
    return if found.empty?
    "kimera redefined #{found.size} method(s) the suite took as a Method object while it loaded " \
      "(#{found.first(SHOWN).map(&:first).join(", ")}): the one taken is no longer == the method and still runs " \
      "the code as loaded, where no mutant reaches; leave its file out of the run (#{excludes(found)})"
  end

  private

  def excludes(found) = found.map(&:last).uniq.map { |file| "--exclude #{file}" }.join(" ")

  def stale
    GC.start
    home = "#{canonical(File.expand_path(@root))}/"
    KINDS.flat_map { |kind| ObjectSpace.each_object(kind).filter_map { |taken| described(taken, home) } }.uniq
  end

  def described(taken, home)
    file, line = taken.source_location
    path = canonical(file)
    return unless path&.start_with?(home) && replaced?(taken, file)
    shown = path.delete_prefix(home)
    ["#{named(taken.owner, taken.name)} at #{shown}:#{line}", shown]
  end

  def named(owner, name) = owner.singleton_class? ? "#{owner.attached_object.inspect}.#{name}" : "#{owner}##{name}"

  def replaced?(taken, file)
    current = LOOKUP.bind_call(taken.owner, taken.name)
    current != unbound(taken) && canonical(current.source_location&.first) == canonical(file)
  rescue NameError
    false
  end

  def unbound(taken) = taken.is_a?(Method) ? taken.unbind : taken

  def canonical(path) = Kimera::Execution::Origin.new(path).canonical
end
