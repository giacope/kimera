# frozen_string_literal: true

module Kimera
  module Frameworks
  end
end

class Kimera::Frameworks::Selection
  def initialize(ids, tests)
    @ids = ids
    @tests = tests
  end

  def name = named(@ids.first)

  def file = ""

  def to_h = listed.to_h { |id| [id, { "name" => named(id) }.merge(located(id))] }

  def to_s = "rspec #{listed.join(" ")} --order defined"

  def plain(_out) = []

  def failed(_output, _out) = []

  private

  def named(id) = id

  def located(_id) = {}

  def listed = @ids & known

  def known = @tests.test_ids
end
