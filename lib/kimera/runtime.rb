# frozen_string_literal: true

require "tmpdir"

module Kimera
end

# rubocop:disable-next Kata/FrozenState, Kata/NoSetter -- the process-wide mutation switch every thread and Ractor reads
class Kimera::Runtime < Module
  SOURCE_PATH = File.expand_path(__FILE__)
  ANCESTRY = Module.instance_method(:ancestors)

  Ledger =
    Struct.new(:ids, :spill) do
      def push(id)
        ids[id] = true
      end

      def drain!
        absorb
        touched = ids.keys
        ids.clear
        touched
      end

      def leak = self.spill ||= File.join(Dir.tmpdir, "kimera-ledger-#{Process.pid}-#{object_id}-#{rand(1 << 32)}")

      def absorb
        return unless spill && File.exist?(spill)
        File.foreach(spill) { |line| ids[Integer(line)] = true }
        File.delete(spill)
      end
    end

  Spill =
    Struct.new(:leak, :ids) do
      def push(id)
        return if ids.key?(id)
        ids[id] = true
        File.write(leak, "#{id}\n", mode: "a")
      end
    end

  NONE = [].freeze

  attr_reader :active

  def initialize
    super
    @active = nil
    @overlaying = false
    @ledgers = NONE
    @spills = NONE
  end

  def active=(id)
    chosen = id && Integer(id)
    hidden.switch(chosen) unless chosen == @active
    @active = chosen
  end

  def active?(id)
    record(id)
    @active == id
  end

  def start!
    ledger = Ledger.new({})
    @ledgers = [*@ledgers, ledger].freeze
    publish
    ledger
  end

  def stop!(ledger)
    return if @ledgers.empty?
    @ledgers = @ledgers.reject { |open| open.equal?(ledger) }.freeze
    publish
    ledger.drain!
  end

  def reset! = self.active = nil

  def during(id)
    previous = @active
    self.active = id
    yield
  ensure
    self.active = previous
  end

  def overlaying? = @overlaying

  def overlay
    @overlaying = true
    yield
  ensure
    @overlaying = false
  end

  def privatize(id, owner, name)
    hidden.register(Integer(id), Flip.new(owner, owner.instance_method(name), []), @active)
    self
  end

  def survey! = hidden.survey

  def leaks = @ledgers.map(&:leak)

  def forked!(paths)
    @ledgers = paths.map { Spill.new(it, {}) }
    publish
  end

  private

  def record(id)
    @ledgers.each { |ledger| ledger.push(id) }
  rescue Ractor::IsolationError
    remote(id)
  end

  def remote(id)
    seen = Ractor.current[:kimera_reached] ||= {}
    return if seen.key?(id)
    seen[id] = true
    @spills.each { |path| File.write(path, "#{id}\n", mode: "a") }
  end

  def publish = @spills = Ractor.make_shareable(leaks)

  def hidden = @_hidden ||= Hidden.new({}, [])
end

Kimera::Runtime::Hidden =
  Struct.new(:flips, :concealed) do
    def switch(id)
      concealed.each(&:reveal).clear
      flip = flips[id]
      concealed << flip.tap(&:conceal) if flip
    end

    def register(id, flip, active)
      flips[id] = flip
      concealed << flip.tap { it.conceal([flip.owner]) } if active == id
    end

    def survey = Kimera::Runtime::Survey.new(flips.values.reject(&:holders)).run
  end

Kimera::Runtime::Survey =
  Data.define(:flips) do
    def run
      return if flips.empty?
      found = below
      flips.each { |flip| flip.holders = found.fetch(flip.owner) }
    end

    def below
      found = flips.to_h { |flip| [flip.owner, [flip.owner]] }.compare_by_identity
      ObjectSpace.each_object(Module) { |each| place(found, each) }
      found
    end

    def place(found, each)
      Kimera::Runtime::ANCESTRY.bind_call(each).each { |above| found[above]&.push(each) unless above.equal?(each) }
    end
  end

Kimera::Runtime::Flip =
  Struct.new(:owner, :definition, :names, :holders) do
    def conceal(within = surveyed)
      self.names = within.flat_map { |holder| held(holder).map { |name| [holder, name] } }
      expose(:private)
    end

    def surveyed
      Kimera::Runtime::Survey.new([self]).run unless holders
      holders
    end

    def reveal
      expose(:public)
      names.clear
    end

    def expose(visibility)
      names.each { |holder, name| holder.__send__(visibility, name) }
      [owner, *names.map(&:first)].uniq.each { |holder| cleared(holder) }
    end

    def cleared(holder) = holder.respond_to?(:clear_action_methods!) && holder.clear_action_methods!

    def held(holder)
      holder.public_instance_methods(false).select { |name| same?(holder.instance_method(name)) }
    end

    def same?(method)
      method == definition ||
        (method.original_name == definition.original_name && method.source_location == definition.source_location)
    end
  end

module Kimera::Runtime::Forks
  def _fork
    Kimera::RUNTIME.survey!
    leaks = Kimera::RUNTIME.leaks
    super.tap { |pid| Kimera::RUNTIME.forked!(leaks) if pid.zero? && leaks.any? }
  end
end

Kimera::RUNTIME = Kimera::Runtime.new unless Kimera.const_defined?(:RUNTIME, false)
Process.singleton_class.prepend(Kimera::Runtime::Forks) unless Process.singleton_class < Kimera::Runtime::Forks
