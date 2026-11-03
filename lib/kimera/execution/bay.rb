# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::Bay
  def initialize(mirror, slot = nil, synth = nil)
    @mirror = mirror
    @slot = slot
    @synth = synth
  end

  def stage(root, file, id)
    source = File.read(File.join(root, file), encoding: Encoding::UTF_8)
    target = File.join(@mirror, file)
    File.write(target, @synth.bake(file, source, id))
    [source, target]
  end

  def command(plan, locations, ledger, first:) = plan.command(@mirror, locations, ledger, first: first, slot: @slot)

  def start(command, errors)
    env, invocation = command
    Process.spawn(env, *invocation, chdir: @mirror, pgroup: true, out: File::NULL, err: errors)
  end

  def moved(mirror) = Kimera::Execution::Bay.new(mirror, @slot, @synth)
end
