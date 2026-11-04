# frozen_string_literal: true

require "json"

module KimeraEval
  class Record
    def initialize(out, baseline)
      @out = out
      @baseline = baseline
    end

    def finished(board, out, errors)
      worse = @baseline ? board.failing - recorded(board) : []
      board.write(@out)
      out.puts(board.markdown)
      errors.puts("eval: worse than #{@baseline}: #{worse.join(" ")}") unless worse.empty?
      worse.empty? ? 0 : 1
    end

    private

    def recorded(board) = board.failing(JSON.parse(File.read(@baseline, encoding: Encoding::UTF_8)).fetch("cases"))
  end
end
