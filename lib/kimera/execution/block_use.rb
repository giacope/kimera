# frozen_string_literal: true

require_relative "../parsing/document"
require_relative "../rewrite/numbered_params"
require_relative "block_use/source"

module Kimera
  module Execution
  end
end

class Kimera::Execution::BlockUse
  REASON =
    "its mutant leaves its method no use of the block passed to it, which Ruby settles as it compiles the " \
      "method, and the warm overlay compiles every mutant of the method into one; the suite reports an ignored " \
      "block, so a warm survivor is judged again in a fresh mirror against the tests near its file"

  def initialize(registry, root)
    @registry = registry
    @given = root
  end

  def revisit!
    return unless warned?
    @registry.files.each do |file|
      source = Kimera::Execution::BlockUse::Source.new(tree(file))
      @registry.at(file).each { |point| point.revisit!(REASON) if open?(point) && source.drops?(point) }
    end
  end

  private

  def warned? = $VERBOSE || (!$VERBOSE.nil? && Warning[:strict_unused_block])

  def root = @_root ||= File.expand_path(@given)

  def tree(file) = Kimera::Rewrite::NumberedParams.new(Kimera::Syntax::Document.new(root, file).result.value).normalize

  def open?(point) = point.safe? && !point.revisit
end
