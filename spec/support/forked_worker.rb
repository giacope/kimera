# frozen_string_literal: true

module WorkerPipes
  # Yields the child's pipe ends; returns [pid, request writer, response reader].
  def forked
    request = IO.pipe
    response = IO.pipe
    pid =
      fork do
        request.last.close
        response.first.close
        yield(request.first, response.last)
      end
    [request.first, response.last].each(&:close)
    [pid, request.last, response.first]
  end

  # A fake worker's loop: hands each requested mutant id to the block, then
  # says done.
  def serving(request, response)
    request.each_line { |line| yield(JSON.parse(line)["id"]) }
    response.puts(JSON.generate(t: "done"))
    response.close
  end

  # A fake worker's verdict on one mutant: start, result, any extra lines, ready.
  def judged(response, id, status, *extra)
    result = JSON.generate(t: "result", id: id, status: status, ms: 1, fails: [])
    response.puts(JSON.generate(t: "start", id: id), result, *extra, JSON.generate(t: "ready"))
    response.flush
  end
end

RSpec.configure { |config| config.include(WorkerPipes) }
