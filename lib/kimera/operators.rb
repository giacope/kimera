# frozen_string_literal: true

require_relative "error"
require_relative "operators/argument_drop"
require_relative "operators/arithmetic"
require_relative "operators/assignment_deletion"
require_relative "operators/base"
require_relative "operators/boolean_connective"
require_relative "operators/boolean_literal"
require_relative "operators/catalog"
require_relative "operators/chain_link_deletion"
require_relative "operators/collection_literal"
require_relative "operators/comparison"
require_relative "operators/conditional"
require_relative "operators/default_argument"
require_relative "operators/element_drop"
require_relative "operators/ensure_clause"
require_relative "operators/index_fetch"
require_relative "operators/kernel_coercion"
require_relative "operators/keyword_drop"
require_relative "operators/method_unwrap"
require_relative "operators/negation"
require_relative "operators/nil_literal"
require_relative "operators/numeric_literal"
require_relative "operators/op_assign"
require_relative "operators/rails_association"
require_relative "operators/rails_callback"
require_relative "operators/rails_permit"
require_relative "operators/rails_validation"
require_relative "operators/range"
require_relative "operators/regexp_anchor"
require_relative "operators/regexp_literal"
require_relative "operators/regexp_quantifier"
require_relative "operators/rescue_clause"
require_relative "operators/respond_to_guard"
require_relative "operators/return_value"
require_relative "operators/safe_navigation"
require_relative "operators/selector_swap"
require_relative "operators/statement_deletion"
require_relative "operators/string_literal"
require_relative "operators/super_call"
require_relative "operators/symbol_literal"
require_relative "operators/visibility"

module Kimera
  module Operators
    ALL = [
      Comparison, BooleanConnective, BooleanLiteral, StatementDeletion, Arithmetic, Negation, SafeNavigation,
      Conditional, NumericLiteral, StringLiteral, CollectionLiteral, Range, MethodUnwrap, ReturnValue,
      SelectorSwap, RegexpLiteral, RailsPermit, RailsValidation, RailsCallback, RailsAssociation, ElementDrop,
      ArgumentDrop, OpAssign, IndexFetch, KernelCoercion, RespondToGuard, SymbolLiteral, DefaultArgument,
      ChainLinkDeletion, SuperCall, RescueClause, EnsureClause, AssignmentDeletion, NilLiteral, RegexpAnchor,
      RegexpQuantifier, KeywordDrop, Visibility
    ].freeze

    DEFAULT_KEYS = [
      Comparison, BooleanConnective, BooleanLiteral,
      StatementDeletion, Negation, Conditional
    ].map { it.new.key }.freeze

    RAILS_KEYS = [RailsPermit, RailsValidation, RailsCallback, RailsAssociation].map { it.new.key }.freeze

    CATALOG = Catalog.new(ALL, RAILS_KEYS)

    def self.build(keys: DEFAULT_KEYS) = CATALOG.build(keys: keys)

    def self.register(*klasses)
      CATALOG.register(*klasses)
      self
    end
  end
end
