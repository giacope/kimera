# frozen_string_literal: true

require "json"
require_relative "../runtime"
require_relative "../synthesis/overlay"
require_relative "child_process"
require_relative "overlay_guards"
require_relative "verdicts"

class Kimera::Execution::Reload
  Failure =
    Data.define(:exception) do
      def message = "#{exception.class}: #{exception.message}"
    end
  include Kimera::Execution::ChildProcess

  Errand =
    Struct.new(:id, :reader, :writer) do
      def parent!
        writer.close
      end

      def child!
        reader.close
      end

      def emit(payload)
        writer.puts(payload)
        writer.close
      end

      def await(deadline, &)
        return reader.gets if reader.wait_readable(deadline)
        yield
        nil
      ensure
        reader.close
      end
    end

  def initialize(registry:, adapter:, isolation:, root:)
    @registry = registry
    @adapter = adapter
    @isolation = isolation
    @root = root
  end

  def run(id, deadline:)
    errand = Errand.new(id, *IO.pipe)
    collect(errand, child(errand), deadline)
  end

  private

  def child(errand)
    fork { work(errand) }.tap { errand.parent! }
  end

  def work(errand)
    errand.child!
    silence!
    errand.emit(report(errand.id))
    exit!(0)
  end

  def report(id)
    status, fails = evaluate(id)
    JSON.generate(id: id, status: status.to_s, fails: fails)
  end

  def collect(errand, pid, deadline)
    line = errand.await(deadline) { kill(pid) }
    reap(pid)
    verdict(errand.id, line)
  end

  def evaluate(id)
    mutate(id).verdict
  rescue StandardError, ScriptError => error
    [:error, [Failure.new(error).message]]
  end

  def mutate(id)
    file = verdicts.point(id).file
    overlay(file, File.join(File.expand_path(@root), file), id)
    Kimera::Runtime.active = nil
    @isolation.around { @adapter.run(@adapter.test_ids) }
  end

  def overlay(file, path, id)
    baked = Kimera::Overlay.new(@registry).bake(file, File.read(path, encoding: Encoding::UTF_8), id)
    Kimera::Execution::OverlayGuards.overlay { Kimera::Overlay.evaluate(baked, path) }
  end

  def verdict(id, line)
    return verdicts.unjudged(id, "reload worker produced no result") unless line
    message = parse(line)
    message ? verdicts.parse(message) : verdicts.unjudged(id, "reload worker output unparseable")
  end

  def verdicts
    Kimera::Execution::Verdicts.new(@registry)
  end
end
