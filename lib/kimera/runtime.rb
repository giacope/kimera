# frozen_string_literal: true

require "tmpdir"

module Kimera
end

# rubocop:disable-next Kata/FrozenState -- the process-wide mutation switch every thread and Ractor reads
class Kimera::Runtime < Module
  SOURCE_PATH = File.expand_path(__FILE__)

  Ledger =
    Struct.new(:ids, :spill) do
      private(*members)
      def initialize(ids = {}, spill = nil) = super

      def push(id)
        ids[id] = true
      end

      def drain!
        absorb
        touched = ids.keys
        ids.clear
        touched
      end

      def spilled = Kimera::Runtime::Spill.new(leak, {})
      private
      def leak(dir = Dir.tmpdir, random = Random)
        self.spill ||= File.join(dir, "kimera-ledger-#{Process.pid}-#{object_id}-#{random.rand(1 << 32)}")
      end

      def absorb
        return unless spill && File.exist?(spill)
        File.foreach(spill) { |line| ids[Integer(line)] = true }
        File.delete(spill)
      end
    end

  Spill =
    Struct.new(:leak, :ids) do
      private(*members)
      def push(id)
        return if ids.key?(id)
        ids[id] = true
        write(id)
      end

      def write(id) = File.write(leak, "#{id}\n", mode: "a")

      def spilled = Kimera::Runtime::Spill.new(leak, {})
    end

  NONE = [].freeze

  def initialize
    super
    @active = nil
    @ledgers = NONE
    @spills = NONE
  end

  def active?(id)
    record(id) # rubocop:disable Kata/CommandQuery -- the woven guard's one call marks its mutant reached and answers whether it is on; two calls would double every guard's cost
    @active == id
  end

  def during(id, *ledgers)
    previous = @active
    choose(id)
    opened(ledgers)
    yield
  ensure
    closed(ledgers)
    choose(previous)
  end

  def privatize(id, owner, name)
    hidden.register(Integer(id), owner, Flip.new(owner, owner.instance_method(name), []), @active)
    self
  end

  def forking
    hidden.survey
    spills = @ledgers.map(&:spilled)
    yield.tap { |pid| forked!(spills) if pid.zero? && spills.any? }
  end

  private

  def choose(id)
    chosen = id && Integer(id)
    hidden.switch(chosen) unless chosen == @active
    @active = chosen
  end

  def opened(ledgers)
    return if ledgers.empty?
    @ledgers = [*@ledgers, *ledgers].freeze
    publish
  end

  def closed(ledgers)
    return if ledgers.empty?
    @ledgers = @ledgers.reject { |open| ledgers.any? { open.equal?(it) } }.freeze
    publish
  end

  def forked!(spills)
    @ledgers = spills.freeze
    publish
  end

  def record(id)
    @ledgers.each { |ledger| ledger.push(id) }
  rescue Ractor::IsolationError
    remote(id)
  end

  def remote(id)
    seen = Ractor.current[:kimera_reached] ||= {}
    return if seen.key?(id)
    seen[id] = true
    @spills.each { |spill| spill.write(id) }
  end

  def publish = @spills = Ractor.make_shareable(@ledgers.map(&:spilled))

  def hidden(kind = Hidden) = @_hidden ||= kind.new({}, [], {}.compare_by_identity)
end

Kimera::Runtime::Hidden =
  Struct.new(:flips, :concealed, :homes) do
    private(*members)
    def switch(id)
      concealed.each(&:reveal).clear
      owner, flip = flips[id]
      concealed << flip.tap { it.conceal(holders(owner, flip)) } if flip
    end

    def register(id, owner, flip, active)
      flips[id] = [owner, flip]
      concealed << flip.tap { it.conceal([owner]) } if active == id
    end

    def survey
      pending = flips.values.reject { |_, flip| homes.key?(flip) }
      return if pending.empty?
      found = Kimera::Runtime::Survey.new(pending.map(&:first).uniq).run
      pending.each { |owner, flip| homes[flip] = found.fetch(owner) }
    end
    private
    def holders(owner, flip) = homes[flip] ||= Kimera::Runtime::Survey.new([owner]).run.fetch(owner)
  end

Kimera::Runtime::Survey =
  Data.define(:owners) do
    private(*members)
    inherits = Module.instance_method(:<)
    def run
      found = owners.to_h { |owner| [owner, [owner]] }.compare_by_identity
      ObjectSpace.each_object(Module) { |each| place(found, each) }
      found
    end
    define_method(:place) do |found, each|
      owners.each { |owner| found[owner] << each if inherits.bind_call(each, owner) }
    end
    private :place
  end

Kimera::Runtime::Flip =
  Struct.new(:owner, :definition, :names) do
    private(*members)
    def conceal(within)
      self.names = within.flat_map { |holder| held(holder).map { |name| [holder, name] } }
      expose(:private)
    end

    def reveal
      expose(:public)
      names.clear
    end
    private
    def expose(visibility)
      # rubocop:disable-next Kata/NoReflection -- a visibility mutant makes the project's own method private in its class, as the mutated source would
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
  def _fork(runtime = Kimera::RUNTIME) = runtime.forking { super() }
end

Kimera::RUNTIME = Kimera::Runtime.new unless Kimera.const_defined?(:RUNTIME, false)
Process.singleton_class.prepend(Kimera::Runtime::Forks) unless Process.singleton_class < Kimera::Runtime::Forks
