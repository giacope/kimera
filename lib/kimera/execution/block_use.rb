# frozen_string_literal: true

require_relative "../parsing/document"
require_relative "../rewrite/numbered_params"
require_relative "block_use/source"

module Kimera
  module Execution
  end
end

class Kimera::Execution::BlockUse
  def initialize(registry, root)
    @registry = registry
    @given = root
  end

  def revisit!
    return unless warned?
    @registry.to_h.each do |file, points|
      source = Kimera::Execution::BlockUse::Source.new(tree(file))
      points.each { |point| point.mark!(Kimera::Reason.blocked) if open?(point) && source.drops?(point) }
    end
  end

  private

  def warned? = $VERBOSE || (!$VERBOSE.nil? && Warning[:strict_unused_block])

  def root = @_root ||= File.expand_path(@given)

  def tree(file, params = Kimera::Rewrite::NumberedParams)
    params.new(Kimera::Syntax::Document.new(root, file).result.value).normalize
  end

  def open?(point) = point.safe? && point.reasons(Kimera::Reason.revisiting).empty?
end
