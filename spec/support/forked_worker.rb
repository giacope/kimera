# frozen_string_literal: true

module WorkerPipes
  # Yields the child's pipe ends; returns [pid, request writer, response reader].
  def forked
    request = IO.pipe
    response = IO.pipe
    [
      fork do
        request.last.close
        response.first.close
        yield(request.first, response.last)
      end.tap do
        request.first.close
        response.last.close
      end,
      request.last,
      response.first
    ]
  end
end

RSpec.configure { |config| config.include(WorkerPipes) }
