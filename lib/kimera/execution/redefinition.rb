# frozen_string_literal: true

require_relative "../support/warnings"
require_relative "origin"

module Kimera
  module Execution
  end
end

class Kimera::Execution::Redefinition
  def initialize(holder, name)
    @holder = holder
    @name = name
  end

  def redefine(method, visibility = self.visibility)
    Kimera::Warnings.silenced.during { @holder.define_method(@name, method) }
    @holder.__send__(visibility, @name)
  end

  def visibility
    return :private if @holder.private_method_defined?(@name)
    @holder.protected_method_defined?(@name) ? :protected : :public
  end
end
