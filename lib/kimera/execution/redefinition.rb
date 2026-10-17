# frozen_string_literal: true

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
    @holder.define_method(@name, method)
    @holder.__send__(visibility, @name)
  end

  def visibility
    return :private if @holder.private_method_defined?(@name)
    @holder.protected_method_defined?(@name) ? :protected : :public
  end
end

Kimera::Execution::Origin =
  Data.define(:path) do
    def canonical = path && File.exist?(path) ? File.realpath(path) : path
  end
