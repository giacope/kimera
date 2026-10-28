# frozen_string_literal: true

require_relative "../parsing/syntax"

module Kimera
  module Frameworks
  end
end

class Kimera::Frameworks::TestTask
  FILES = %w[Rakefile rakefile Rakefile.rb rakefile.rb].freeze
  BUILDERS = %i[new create].freeze
  NAMED = "test"
  QUIET = %i[false_node nil_node].freeze
  CONSTANTS = %i[constant_path_node constant_read_node].freeze
  WARNING = "-w"
  WARNED = "\n  green without `ruby -w`: the Rakefile's Rake::TestTask turns warnings on (its default), as kimera " \
    "does, and the suite fails with them; set `t.warning = false` there if it is not meant to run with warnings"
  UNWARNED = "\n  green under `ruby -w`, as Rake::TestTask runs it by default: the suite needs warnings on " \
    "($VERBOSE); kimera turns them on when the Rakefile's Rake::TestTask keeps `warning` on, or run it with RUBYOPT=-w"

  def initialize(root = ".")
    @root = root
  end

  def flags = warning? ? [WARNING] : []

  def flipped = warning? ? [] : [WARNING]

  def contrast = warning? ? WARNED : UNWARNED

  def install
    return unless warning?
    $VERBOSE = true
    Warning[:deprecated] = true
  end

  def warning?
    task = tasks.find { |each| named(each) == NAMED } || tasks.first
    !task.nil? && !quiet?(task.block)
  end

  private

  def tasks
    rakefile = FILES.map { |name| File.join(@root, name) }.find { |path| File.file?(path) }
    rakefile ? found(Kimera::Syntax.parse(File.read(rakefile)).value) : []
  end

  def found(node)
    own = task?(node) ? [node] : []
    own + node.compact_child_nodes.flat_map { |child| found(child) }
  end

  def task?(node)
    node.type == :call_node && BUILDERS.include?(node.name) && CONSTANTS.include?(node.receiver&.type) &&
      node.receiver.name == :TestTask
  end

  def named(task)
    first = value(task)
    %i[symbol_node string_node].include?(first&.type) ? first.unescaped : NAMED
  end

  def quiet?(node)
    return false unless node
    silenced?(node) || node.compact_child_nodes.any? { |child| quiet?(child) }
  end

  def silenced?(node) = node.type == :call_node && node.name == :warning= && QUIET.include?(value(node).type)

  def value(call) = call.arguments&.arguments&.first
end
