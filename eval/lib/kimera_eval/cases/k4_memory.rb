# frozen_string_literal: true

module KimeraEval
  class MemoryCase < Case
    ID = "K4"
    TITLE = "Coverage memory stays bounded in a hot loop"
    LIMIT_MB = 150
    MODES = [%w[--jobs 1], %w[--jobs 2]].freeze

    def call
      runs = MODES.to_h { |mode| [mode.join(" "), measure(mode)] }
      peak = runs.values.map { |run| run["max_process_mb"] }.max
      wall = runs.values.sum { |run| run["wall_s"] }.round(1)
      { "pass" => peak < LIMIT_MB, "summary" => { "peak_rss_mb" => peak, "wall_s" => wall }, "runs" => runs }
    end

    private

    def measure(mode)
      dir = sandbox.copy(fixture("loop"))
      result = checkout.cli("run", *mode, "--report", File.join(dir, "tmp", "loop.json"), "--no-progress", chdir: dir)
      result.rss.merge("wall_s" => result.wall.round(2), "exit" => result.code)
        .merge("tail" => result.output.lines.last(2).join)
    end
  end
end
