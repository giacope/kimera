# frozen_string_literal: true

require "json"
require "time"

module KimeraEval
  class Scoreboard
    HEADER = ["| Gap | Case | Pass | Headline |", "| --- | --- | --- | --- |"].freeze

    def initialize(checkout, clock: Time)
      @checkout = checkout
      @clock = clock
      @cases = {}
    end

    def record(kind, result, wall)
      @cases[kind::ID] ||= { "title" => kind::TITLE, "wall_s" => wall.round(1) }.merge(result)
    end

    def to_h
      { "kimera" => @checkout.path, "revision" => @checkout.revision, "ruby" => RUBY_VERSION }
        .merge("at" => @clock.now.utc.iso8601, "cases" => @cases)
    end

    def write(path)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "#{JSON.pretty_generate(to_h)}\n")
    end

    def failing(cases = @cases) = cases.reject { |_id, result| result["pass"] }.keys

    def markdown = [*HEADER, *@cases.map { |id, result| line(id, result) }].join("\n")

    private

    def line(id, result) = "| #{id} | #{result["title"]} | #{mark(result)} | #{headline(result)} |"

    def mark(result) = result["pass"] ? "yes" : "**no**"

    def headline(result)
      error = result["error"]
      return "error: #{error.lines.first&.strip}" if error
      result.fetch("summary") { {} }.map { |key, value| "#{key}=#{value}" }.join(", ")
    end
  end
end
