# frozen_string_literal: true

class Kimera::CLI::Checklist
  def initialize(io, errors)
    @io = io
    @errors = errors
  end

  def shown(check)
    status, text = check
    @io.puts("#{status} #{text}")
    @io.flush
    check
  end

  def verdict(checks)
    failed = checks.count { |status,| status == "✗" }
    return 0 if failed.zero?
    @errors.puts("kimera: doctor found #{failed} blocking issue(s)")
    1
  end
end
