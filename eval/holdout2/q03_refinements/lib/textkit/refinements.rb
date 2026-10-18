# frozen_string_literal: true

module TextKit
  # String and Integer helpers, only visible in files that say
  # `using TextKit::Refinements`.
  module Refinements
    MINOR_WORDS = %w[a an and at by for in of on or the to].freeze

    refine String do
      def squish
        strip.gsub(/\s+/, " ")
      end

      def truncate_words(limit, omission: "...")
        words = squish.split(" ")
        return squish if words.length <= limit

        words.first(limit).join(" ") + omission
      end

      def title_case
        squish.split(" ").each_with_index.map do |word, index|
          last = index == squish.count(" ")
          if index.positive? && !last && MINOR_WORDS.include?(word.downcase)
            word.downcase
          else
            word[0].upcase + word[1..].downcase
          end
        end.join(" ")
      end

      def slugify(separator = "-")
        downcase.gsub(/[^a-z0-9]+/, separator).delete_prefix(separator).delete_suffix(separator)
      end
    end

    refine Integer do
      def ordinalize
        suffix =
          if (11..13).cover?(abs % 100) then "th"
          else
            { 1 => "st", 2 => "nd", 3 => "rd" }.fetch(abs % 10, "th")
          end
        "#{self}#{suffix}"
      end
    end
  end
end
