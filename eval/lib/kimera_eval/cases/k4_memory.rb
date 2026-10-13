# frozen_string_literal: true

module KimeraEval
  # K4: peak memory while coverage records a hot loop. Each loop iteration
  # evaluates several guards; a ledger that keeps every evaluation grows with
  # the iteration count, one that keeps each id once does not.
  class MemoryCase < Case
    ID = "K4"
    TITLE = "Coverage memory stays bounded in a hot loop"
    LIMIT_MB = 150

    def call
      runs = [%w[--jobs 1], %w[--jobs 2]].to_h { |mode| [mode.join(" "), measure(mode)] }
      peak = runs.values.map { |run| run["max_process_mb"] }.max
      { "pass" => peak < LIMIT_MB, "summary" => { "peak_rss_mb" => peak, "wall_s" => runs.values.sum { |run| run["wall_s"] }.round(1) } }
        .merge("runs" => runs)
    end

    private

    def measure(mode)
      dir = sandbox.copy(fixture("loop"))
      result = checkout.kimera("run", *mode, "--report", File.join(dir, "tmp", "loop.json"), "--no-progress", chdir: dir)
      result.rss.merge("wall_s" => result.wall.round(2), "exit" => result.code, "tail" => result.output.lines.last(2).join)
    end
  end
end
