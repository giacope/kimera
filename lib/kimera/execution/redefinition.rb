# frozen_string_literal: true

module Kimera
  module Execution
  end
end

module Kimera::Execution::Redefinition
  module_function

  def redefine(holder, name, method, visibility = visibility(holder, name))
    holder.define_method(name, method)
    holder.__send__(visibility, name)
  end

  def visibility(holder, name)
    return :private if holder.private_method_defined?(name)
    holder.protected_method_defined?(name) ? :protected : :public
  end

  def canonical(path) = path && File.exist?(path) ? File.realpath(path) : path

  def source(method) = method.source_location&.first
end
