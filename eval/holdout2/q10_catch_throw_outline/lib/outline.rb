# frozen_string_literal: true

# Numbered document outline built on one process-wide stack of open
# sections. `skip!` leaves the current section early with throw; the
# section is closed in an ensure whichever way the block exits.
module Outline
  class NotInSection < StandardError; end

  MAX_DEPTH = 4
  Frame = Struct.new(:title, :number)

  class << self
    def stack
      @stack ||= []
    end

    def depth
      stack.size
    end

    def path(separator = " > ")
      stack.map(&:title).join(separator)
    end

    def number
      stack.map(&:number).join(".")
    end

    def section(title, number = 1)
      raise ArgumentError, "title required" if title.to_s.strip.empty?
      raise ArgumentError, "nested deeper than #{MAX_DEPTH}" if depth >= MAX_DEPTH

      stack.push(Frame.new(title.strip, number))
      begin
        catch(:skip_section) { yield }
      ensure
        stack.pop
      end
    end

    def skip!
      raise NotInSection, "skip! outside a section" if depth.zero?

      throw :skip_section, :skipped
    end

    # tree: { "Title" => { "Child" => {} } }. Titles starting with "_" are
    # drafts: they are skipped and do not use up a number.
    def render(tree, indent: 2, numbered: true)
      raise ArgumentError, "indent must not be negative" if indent.negative?

      lines = []
      walk(tree, lines, indent, numbered)
      lines
    end

    private

    def walk(tree, lines, indent, numbered)
      position = 0
      tree.each do |title, children|
        section(title, position + 1) do
          skip! if title.start_with?("_")
          position += 1
          prefix = numbered ? "#{number} " : ""
          lines << "#{' ' * (indent * (depth - 1))}#{prefix}#{title}"
          walk(children, lines, indent, numbered) unless children.empty?
        end
      end
    end
  end
end
