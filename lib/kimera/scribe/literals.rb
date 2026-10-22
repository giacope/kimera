# frozen_string_literal: true

module Kimera
  class Scribe
    class Keyword < Form
      WORDS = {
        true: "true", false: "false", nil: "nil", self: "self", zsuper: "super", redo: "redo", retry: "retry",
        forward_arg: "...", forwarded_args: "...", forwarded_restarg: "*", forwarded_kwrestarg: "**",
        kwnilarg: "**nil", match_nil_pattern: "**nil", cbase: "::", __FILE__: "__FILE__", __LINE__: "__LINE__",
        __ENCODING__: "__ENCODING__", lambda: "->", empty_else: ""
      }.freeze
      TYPES = WORDS.keys.freeze

      def text = WORDS.fetch(type)
    end

    class Variable < Form
      TYPES = %i[ivar gvar cvar match_var].freeze

      def text = children.first.to_s
    end

    class Local < Form
      TYPES = %i[lvar].freeze
      IMPLICIT = /\A(?:_[1-9]|it)\z/

      def text
        name = children.first
        return name.to_s if @pen.local?(name) || name.match?(IMPLICIT)
        raise(Unbound, "kimera cannot write this read of #{name}: nothing binds the local there")
      end
    end

    class Reference < Form
      TYPES = %i[nth_ref back_ref].freeze

      def text = type == :nth_ref ? "$#{children.first}" : children.first.to_s
    end

    class Numeral < Form
      TYPES = %i[int float rational complex].freeze

      def text = Number.new(children.first).text
    end

    class Atom < Form
      TYPES = %i[sym].freeze

      def text = Name.new(children.first).symbol
    end

    class Characters < Form
      TYPES = %i[str].freeze

      def text = %("#{Quote.new(children.first).text}")
    end

    class Const < Form
      TYPES = %i[const].freeze

      def text
        scope, name = children
        return name.to_s unless scope
        scope.type == :cbase ? "::#{name}" : "#{part(0, Level::PRIMARY)}::#{name}"
      end
    end
  end
end
