# frozen_string_literal: true

require_relative "../parsing/syntax"
require_relative "../support/warnings"
require_relative "redefinition"

module Kimera
  module Execution
  end
end

# A `def` inside a block handed to a DSL (`RSpec.shared_examples_for`,
# `shared_context`, `Module.new`) defines its method on whatever module runs
# the block, which the source cannot name: re-running the file defines nothing
# there. So before the overlay runs, every module whose method was loaded from
# such a def is noted, and afterwards the woven def is defined on each one,
# inside the def's own lexical scope, with the visibility it had. Only a file
# with such a def has the heap searched for them.
#
# The def is compiled on its own, so its lexical scope is written around it:
# the comments above the file's first line of code (its magic comments, such
# as frozen_string_literal), and the file and each class or module around it
# with the refinements a `using` there had activated by the def's line. Left
# out, a def calling a refined method raised NoMethodError under kimera only.
class Kimera::Execution::BlockMethods
  Site =
    Data.define(:name, :line, :span, :preamble, :nesting, :text) do
      def code = "#{head}#{text}\nend#{"; end" * nesting.size}"
      def compiled(path) = RubyVM::InstructionSequence.compile(code, path, path, line - head.count("\n")).eval
      private
      def head = "#{preamble}#{nesting.join}proc do\n"
    end
  Scope =
    Data.define(:opening, :usings) do
      def to_s = "#{opening}#{usings.join}"
    end
  Held = Data.define(:holder, :site, :visibility)
  OPENERS = { Prism::ClassNode => "class", Prism::ModuleNode => "module" }.freeze
  BLOCKS = [Prism::BlockNode, Prism::LambdaNode].freeze
  LOOKUP = Module.instance_method(:instance_method)
  PUBLIC = Module.instance_method(:method_defined?)
  HIDDEN = Module.instance_method(:private_method_defined?)
  INHERITED = false

  def initialize(file, loaded, woven, locations)
    @file = file
    @loaded = loaded
    @woven = woven
    @locations = locations
  end

  def adopt
    held = holders
    yield.tap { held.each { |entry| install(entry) } }
  end

  private

  def path = @_path ||= Kimera::Execution::Origin.new(@file).canonical

  def holders
    wanted = sites
    return [] if wanted.empty?
    ObjectSpace.each_object(Module).flat_map { |holder| wanted.filter_map { |site| held(holder, site) } }
  end

  def sites = pairs.filter_map { |(site, woven)| woven.with(line: site.line) if live?(site) }

  def pairs
    woven = collect(@woven).group_by(&:name)
    collect(@loaded).group_by(&:name).flat_map do |name, mine|
      theirs = woven.fetch(name, [])
      theirs.size == mine.size ? mine.zip(theirs) : []
    end
  end

  def live?(site)
    from, to = site.span
    @locations.any? { |location| location.inside?(from, to) }
  end

  def collect(source)
    root = Kimera::Syntax.parse(source).value
    walk(root, [Scope.new(source.byteslice(0, root.location.start_offset), [])], root)
  end

  def walk(node, nesting, scope)
    return defined(node, nesting, scope) if node.is_a?(Prism::DefNode)
    return refined(node, nesting.last) if using?(node)
    keyword = OPENERS[node.class]
    return opened(node, [*nesting, Scope.new("#{keyword} #{node.constant_path.slice}; ", [])]) if keyword
    node.compact_child_nodes.flat_map { |child| walk(child, nesting, BLOCKS.include?(node.class) ? node : scope) }
  end

  def using?(node) = node.is_a?(Prism::CallNode) && node.name == :using && node.receiver.nil?

  def refined(node, scope)
    scope.usings << "#{node.slice}; "
    []
  end

  def defined(node, nesting, scope) = BLOCKS.include?(scope.class) && node.receiver.nil? ? [site(node, nesting)] : []

  def opened(node, nesting)
    body = node.body
    body ? walk(body, nesting, node) : []
  end

  def site(node, nesting)
    location = node.location
    file, *openers = nesting.map(&:to_s)
    Site.new(node.name, location.start_line, [location.start_offset, location.end_offset], file, openers, node.slice)
  end

  def held(holder, site)
    name = site.name
    return unless PUBLIC.bind_call(holder, name, INHERITED) || HIDDEN.bind_call(holder, name, INHERITED)
    return unless from?(LOOKUP.bind_call(holder, name), site)
    Held.new(holder, site, Kimera::Execution::Redefinition.new(holder, name).visibility)
  end

  def from?(method, site)
    file, line = method.source_location
    line == site.line && Kimera::Execution::Origin.new(file).canonical == path
  end

  def install(entry)
    holder, site, visibility = entry.deconstruct
    Kimera::Warnings::SILENCED.during { holder.class_exec(&compiled(site)) }
    holder.__send__(visibility, site.name)
  rescue StandardError, ScriptError
    nil
  end

  def compiled(site) = (@_compiled ||= {})[site] ||= site.compiled(@file)
end
