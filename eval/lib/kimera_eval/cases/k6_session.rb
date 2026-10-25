# frozen_string_literal: true

module KimeraEval
  class SessionCase < Case
    ID = "K6"
    TITLE = "--session drops verdicts once the tests change"
    DELETED = /stays shut at 5|shuts above 50/

    def call
      dir = sandbox.copy(fixture("session"))
      session = File.join(dir, "tmp", "session.json")
      verdicts(dir, "first", session)
      prune(dir)
      compare(verdicts(dir, "resumed", session), verdicts(dir, "fresh"))
    end

    private

    def verdicts(dir, name, session = nil)
      path = File.join(dir, "tmp", "#{name}.json")
      FileUtils.mkdir_p(File.dirname(path))
      checkout.cli("run", *(session ? ["--session", session] : []), "--report", path, "--no-progress", chdir: dir)
      JSON.parse(File.read(path)).fetch("results").to_h { |row| [row["key"], row["status"]] }
    end

    def prune(dir)
      spec = File.join(dir, "spec", "gate_spec.rb")
      File.write(spec, File.readlines(spec).grep_v(DELETED).join)
    end

    def compare(resumed, fresh)
      stale = fresh.reject { |key, status| resumed[key] == status }
      { "pass" => stale.empty? && fresh.any?, "summary" => { "stale_verdicts" => stale.size, "mutants" => fresh.size } }
        .merge("stale" => stale.keys.map { |key| "#{key}: resumed #{resumed[key]}, fresh #{fresh[key]}" })
    end
  end
end
