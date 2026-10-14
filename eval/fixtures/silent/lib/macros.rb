module Macros
  def rule(name, &check)
    rules[name] = check
  end

  def rules = @rules ||= {}
end
