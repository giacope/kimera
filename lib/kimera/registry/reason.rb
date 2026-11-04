# frozen_string_literal: true

module Kimera
end

class Kimera::Reason
  CLASS_BODY_REASON = "class-body DSL (runs at load; evaluate with --isolated)"
  BOOT_REASON =
    "its method also runs while the suite loads, and what it computed then (a constant, a table) was " \
      "not mutated, so a warm survivor is judged again in a fresh mirror against the tests near its file"
  ORDER_REASON =
    "no single test reaches it in a fresh process, but the suite does when its tests run in order " \
      "(an earlier test leaves the state it needs), so it is judged in a fresh mirror against the whole suite"
  LOAD_REASON =
    "runs only while the suite loads (a macro or hook called from a class body), " \
      "so warm coverage cannot see it; evaluate with --isolated"
  MACRO_REASON =
    "a lambda handed to a class-body macro (a callback, a default:) that no test reached warm: the warm " \
      "overlay re-declares the macro, which can leave the original lambda registered in front of the " \
      "mutated one, so warm coverage cannot see it; evaluate with --isolated"
  BOUND_REASON = "a lambda a constant holds stays bound, since a registry may keep it; evaluate with --isolated"
  BLOCK_REASON =
    "its mutant leaves its method no use of the block passed to it, which Ruby settles as it compiles the " \
      "method, and the warm overlay compiles every mutant of the method into one; the suite reports an ignored " \
      "block, so a warm survivor is judged again in a fresh mirror against the tests near its file"
  MACRO_KEPT =
    "a lambda handed to a class-body macro: the warm overlay re-declares the macro, and one that adds to a list " \
      "(default_scope, a callback, a validation) keeps the original lambda beside the mutated one, so a warm " \
      "survivor is judged again in a fresh mirror against the tests near its file"
  NEVER = "never executed: the suite never loads this file, so no test can run it"
  NEVER_LOADED =
    "#{NEVER} (kimera did not evaluate it, since loading it would run its top-level code inside the test " \
      "process)".freeze
  UNMUTATABLE = "unmutatable: "
  UNLOADED = /\A#{Regexp.escape(NEVER)}/
  UNWRITTEN = /\A#{UNMUTATABLE}/
  EXACT = ->(text) { /\A#{Regexp.escape(text)}\z/ }
  STUCK = Regexp.union(*[CLASS_BODY_REASON, LOAD_REASON, MACRO_REASON, BOUND_REASON].map(&EXACT), UNLOADED, UNWRITTEN)
  WARM = Regexp.union(*[BLOCK_REASON, MACRO_KEPT].map(&EXACT))

  class << self
    def class_body = new(:reason, CLASS_BODY_REASON)

    def bound = new(:reason, BOUND_REASON)

    def loading = new(:reason, LOAD_REASON)

    def macro = new(:reason, MACRO_REASON)

    def unloaded = new(:reason, NEVER_LOADED, UNLOADED)

    def unloadable(failure) = new(:reason, "#{NEVER} (nor could kimera load it: #{failure})", UNLOADED)

    def unmutatable(detail = "") = new(:reason, "#{UNMUTATABLE}#{detail}", UNWRITTEN)

    def unsafe(text) = new(:reason, text)

    def booted = new(:revisit, BOOT_REASON)

    def kept = new(:revisit, MACRO_KEPT)

    def blocked = new(:revisit, BLOCK_REASON)

    def ordered = new(:revisit, ORDER_REASON)

    def revisit(text) = new(:revisit, text)

    def unsafety = new(:reason, "", //)

    def revisiting = new(:revisit, "", //)

    def unreloadable = new(:reason, "", STUCK)

    def warm = new(:revisit, "", WARM)
  end

  def initialize(slot, text, pattern = EXACT.call(text))
    @slot = slot
    @text = text
    @pattern = pattern
  end

  def mark!(marks, ids)
    marks.mark!(@slot, @text)
    ids
  end

  def held(marks) = marks.texts(@slot).grep(@pattern)

  def unless_covered(coverage, reached, kind = Kimera::Reason::Deferral) = kind.new(coverage, self, reached)

  def to_s = @text
end

require_relative "reason/deferral"
require_relative "reason/guarded"
