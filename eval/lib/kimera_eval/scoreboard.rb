# frozen_string_literal: true

require "json"
require "time"

module KimeraEval
  # Collects case results, writes them as JSON and prints a Markdown table.
  class Scoreboard
    def initialize(checkout)
      @checkout = checkout
      @cases = {}
    end

    def record(kind, result, wall)
      @cases[kind::ID] = { "title" => kind::TITLE, "wall_s" => wall.round(1) }.merge(result)
    end

    def to_h
      { "kimera" => @checkout.path, "revision" => @checkout.revision, "ruby" => RUBY_VERSION }
        .merge("at" => Time.now.utc.iso8601, "cases" => @cases)
    end

    def write(path)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "#{JSON.pretty_generate(to_h)}\n")
    end

    def markdown
      rows = @cases.map { |id, result| "| #{id} | #{result["title"]} | #{mark(result)} | #{headline(result)} |" }
      ["| Gap | Case | Pass | Headline |", "| --- | --- | --- | --- |", *rows].join("\n")
    end

    private

    def mark(result) = result["pass"] ? "yes" : "**no**"

    def headline(result)
      result.fetch("summary") { {} }.map { |key, value| "#{key}=#{value}" }.join(", ").then do |text|
        result["error"] ? "error: #{result["error"].lines.first&.strip}" : text
      end
    end
  end
end
