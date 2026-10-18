# frozen_string_literal: true

using TextKit::Refinements

module TextKit
  # A ranked headline. Slugs are kept unique per process: a repeated title
  # gets "-2", "-3", ... appended.
  class Headline
    MAX_WORDS = 6

    def self.slugs
      @slugs ||= Hash.new(0)
    end

    attr_reader :text, :rank

    def initialize(text, rank: 1)
      raise ArgumentError, "rank must be at least 1" if rank < 1

      @text = text
      @rank = rank
    end

    def display
      "#{rank.ordinalize}: #{text.title_case.truncate_words(MAX_WORDS)}"
    end

    def short?
      text.squish.split(" ").size <= 3
    end

    def slug
      @slug ||= begin
        base = text.slugify
        count = self.class.slugs[base] += 1
        count > 1 ? "#{base}-#{count}" : base
      end
    end
  end
end
