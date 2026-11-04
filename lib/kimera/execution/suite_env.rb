# frozen_string_literal: true

require_relative "env_patch"
require_relative "../frameworks/load_path"

module Kimera
  module Execution
  end
end

class Kimera::Execution::SuiteEnv
  MARK = { "KIMERA" => "1" }.freeze
  SEED = "KIMERA_SEED"
  private_constant(:MARK, :SEED)

  def initialize(env = ENV)
    @env = env
  end

  def to_h = MARK

  def install(seed, paths, env = @env)
    env.update(MARK)
    seed ? env.store(SEED, seed.to_s) : env.delete(SEED)
    Kimera::Frameworks::LoadPath.new([], env: env).share(paths)
  end

  def seeded(seed, env = @env, &) = Kimera::Execution::EnvPatch.new(SEED => seed.to_s).during(env, &)
end
