# frozen_string_literal: true

require_relative "block_methods/survey"
require_relative "origin"

module Kimera
  module Execution
  end
end

class Kimera::Execution::BlockMethods
  def initialize(file, loaded, woven, points)
    @file = file
    @loaded = loaded
    @woven = woven
    @points = points
  end

  def adopt
    held = holders
    yield.tap { held.each { |entry| entry.install(@file) } }
  end

  private

  def path = @_path ||= Kimera::Execution::Origin.new(@file).canonical

  def holders
    wanted = sites
    return [] if wanted.empty?
    ObjectSpace.each_object(Module).flat_map { |holder| wanted.flat_map { |site| site.held(holder, path) } }
  end

  def sites = pairs.filter_map { |(site, woven)| site.over(woven) if site.live?(@points) }

  def pairs
    woven = Kimera::Execution::BlockMethods::Survey.new(@woven).named
    Kimera::Execution::BlockMethods::Survey.new(@loaded).named.flat_map do |name, mine|
      theirs = woven.fetch(name, [])
      theirs.size == mine.size ? mine.zip(theirs) : []
    end
  end
end
