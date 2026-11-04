# frozen_string_literal: true

require_relative "../support/warnings"
require_relative "origin"

module Kimera
  module Execution
  end
end

class Kimera::Execution::Redefinition
  LOOKUP = Module.instance_method(:instance_method)
  PUBLIC = Module.instance_method(:method_defined?)
  HIDDEN = Module.instance_method(:private_method_defined?)
  INHERITED = false

  def initialize(holder, name)
    @holder = holder
    @name = name
  end

  def redefine(method, visibility = self.visibility)
    Kimera::Warnings.silenced.during { @holder.define_method(@name, method) }
    # rubocop:disable-next Kata/NoReflection -- a woven method takes the visibility its original had in the project's class, which only the class's private visibility methods set
    @holder.__send__(visibility, @name)
  end

  def found = own? ? [LOOKUP.bind_call(@holder, @name)] : []

  def held(kind, place, &) = found.select(&).map { |definition| kind.new(self, definition, visibility, place) }

  def reinstall(definer, visibility)
    Kimera::Warnings.silenced.during { @holder.class_exec(&definer) }
    # rubocop:disable-next Kata/NoReflection -- a woven method takes the visibility its original had in the project's class, which only the class's private visibility methods set
    @holder.__send__(visibility, @name)
  end

  def ==(other) = other.is_a?(self.class) && other.key == key

  protected

  def key = [@holder, @name]

  private

  def visibility
    return :private if @holder.private_method_defined?(@name)
    @holder.protected_method_defined?(@name) ? :protected : :public
  end

  def own? = PUBLIC.bind_call(@holder, @name, INHERITED) || HIDDEN.bind_call(@holder, @name, INHERITED)
end
