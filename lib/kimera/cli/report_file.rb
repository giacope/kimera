# frozen_string_literal: true

require "json"
require_relative "../error"

module Kimera
end

class Kimera::CLI
end

module Kimera::CLI::ReportFile
  module_function

  def parse(path)
    JSON.parse(File.read(path))
  rescue JSON::ParserError => error
    raise(Kimera::UsageError, "unreadable report #{path}: #{error.message}")
  end
end
