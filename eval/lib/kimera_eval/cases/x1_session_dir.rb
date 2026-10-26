# frozen_string_literal: true

module KimeraEval
  class FolderCase < Case
    ID = "X1"
    TITLE = "--session into a missing directory saves instead of crashing"

    def call
      dir = sandbox.copy(fixture("session"))
      result = checkout.cli("run", "--session", "tmp/new/session.json", "--no-progress", "--no-report", chdir: dir)
      saved = File.exist?(File.join(dir, "tmp", "new", "session.json"))
      { "pass" => saved && result.code != 1, "summary" => { "saved" => saved, "exit" => result.code } }
    end
  end
end
