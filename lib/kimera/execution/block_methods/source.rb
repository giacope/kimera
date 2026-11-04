# frozen_string_literal: true

class Kimera::Execution::BlockMethods; end

class Kimera::Execution::BlockMethods::Source
  def initialize(preamble, nesting, text)
    @preamble = preamble
    @nesting = nesting
    @text = text
  end

  def compiled(path, line) = RubyVM::InstructionSequence.compile(code, path, path, line - head.count("\n")).eval

  private

  def code = "#{head}#{@text}\nend#{"; end" * @nesting.size}"

  def head = "#{@preamble}#{@nesting.join}proc do\n"
end
