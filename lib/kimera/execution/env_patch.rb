# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::EnvPatch
  def initialize(values)
    @values = values
  end

  def during(env)
    saved = @values.keys.to_h { |name| [name, env.fetch(name, nil)] }
    begin
      env.update(@values)
      yield
    ensure
      saved.each { |name, value| value ? env.store(name, value) : env.delete(name) }
    end
  end
end
