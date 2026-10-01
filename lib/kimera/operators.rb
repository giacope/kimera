# frozen_string_literal: true

require_relative "error"
require_relative "operators/argument_drop"
require_relative "operators/arithmetic"
require_relative "operators/base"
require_relative "operators/boolean_connective"
require_relative "operators/boolean_literal"
require_relative "operators/chain_link_deletion"
require_relative "operators/collection_literal"
require_relative "operators/comparison"
require_relative "operators/conditional"
require_relative "operators/default_argument"
require_relative "operators/element_drop"
require_relative "operators/index_fetch"
require_relative "operators/kernel_coercion"
require_relative "operators/method_unwrap"
require_relative "operators/negation"
require_relative "operators/numeric_literal"
require_relative "operators/op_assign"
require_relative "operators/rails_association"
require_relative "operators/rails_callback"
require_relative "operators/rails_permit"
require_relative "operators/rails_validation"
require_relative "operators/range"
require_relative "operators/regexp_literal"
require_relative "operators/respond_to_guard"
require_relative "operators/return_value"
require_relative "operators/safe_navigation"
require_relative "operators/selector_swap"
require_relative "operators/statement_deletion"
require_relative "operators/string_literal"
require_relative "operators/symbol_literal"

module Kimera
  module Operators
    ALL = [
      Comparison,
      BooleanConnective,
      BooleanLiteral,
      StatementDeletion,
      Arithmetic,
      Negation,
      SafeNavigation,
      Conditional,
      NumericLiteral,
      StringLiteral,
      CollectionLiteral,
      Range,
      MethodUnwrap,
      ReturnValue,
      SelectorSwap,
      RegexpLiteral,
      RailsPermit,
      RailsValidation,
      RailsCallback,
      RailsAssociation,
      ElementDrop,
      ArgumentDrop,
      OpAssign,
      IndexFetch,
      KernelCoercion,
      RespondToGuard,
      SymbolLiteral,
      DefaultArgument,
      ChainLinkDeletion
    ].freeze

    DEFAULT_KEYS = [
      Comparison, BooleanConnective, BooleanLiteral,
      StatementDeletion, Negation, Conditional
    ].map { it.new.key }.freeze

    RAILS_KEYS = [RailsPermit, RailsValidation, RailsCallback, RailsAssociation].map { it.new.key }.freeze

    @registered = ALL.dup

    module_function

    def build(keys: DEFAULT_KEYS)
      requested = expand(keys)
      validate!(requested)
      registered.map(&:new).select { |operator| requested.include?(operator.key) }
    end

    def keys
      registered.map { |klass| key_of(klass) }
    end

    def registered
      @registered
    end

    def register(*klasses)
      klasses.flatten.each { |klass| admit(klass) }
      self
    end

    def reset!
      @registered = ALL.dup
      self
    end

    def admit(klass)
      raise(UsageError, "not an operator class: #{klass.inspect}") unless operator?(klass)
      key = key_of(klass)
      taken = registered.find { |operator| key_of(operator) == key }
      raise(UsageError, "operator key already registered: #{key} (#{taken})") if taken
      registered << klass
    end

    def key_of(klass) = klass.new.key

    def operator?(klass)
      klass.is_a?(Class) && klass < Base
    end

    def custom
      registered - ALL
    end

    def expand(keys)
      Array(keys).map(&:to_s).flat_map { |key| expansion(key) }.uniq
    end

    def groups
      { "all" => keys, "rails" => RAILS_KEYS, "custom" => custom.map { |klass| key_of(klass) } }
    end

    def expansion(key)
      groups.fetch(key) { [key] }
    end

    def vocabulary
      ["all", "rails", "custom", *keys].join(", ")
    end

    def validate!(requested)
      unknown = requested - keys
      return if unknown.empty?
      raise(UsageError, "unknown operator(s): #{unknown.join(", ")} (valid: #{vocabulary})")
    end
  end
end
