# frozen_string_literal: true

class Kimera::Frameworks::MinitestSuite::Selection < Kimera::Frameworks::Selection
  CONSTANT = /\A[A-Z]\w*(?:::[A-Z]\w*)*\z/
  PLAIN = %r{\A[\w./@:+-]+\z}
  FAILED = /^\s*(?:\d+\) )?(?:Failure|Error):\n(.+?)(?: \[[^\]]*\])?:$/

  def initialize(ids, indexed, task)
    super(ids, indexed)
    @task = task
  end

  def file = String(@tests[@ids.first]&.then { |klass, name| declared(klass.name) || definition(klass, name).first })

  def to_s
    "bundle exec ruby #{[*@task.flags, includes].join(" ")} " \
      "-rminitest/autorun -e #{quote(loads)} " \
      "-- -n #{quote("/^(?:#{@ids.map { |id| Regexp.escape(id) }.join("|")})$/")} --seed #{Minitest.seed}"
  end

  def plain(_out) = ["sh", "-c", to_s]

  def failed(output, _out) = output.scan(FAILED).flatten

  private

  def located(id) = { "location" => definition(*@tests.fetch(id)).join(":") }

  def known = @tests.keys

  def includes
    flags = Kimera::Frameworks::LoadPath.new(@ids.filter_map { |id| origin(id) }).flags
    flags.each_slice(2).map { |flag, dir| "#{flag}#{shell(dir)}" }.join(" ")
  end

  def shell(word) = word.match?(PLAIN) ? word : quote(word)

  def loads
    @ids.filter_map { |id| origin(id) }.uniq.map { |file| "require File.expand_path(#{file.dump})" }.join("; ")
  end

  def origin(id) = @tests[id]&.then { |found| definition(*found).first }

  def declared(named) = named&.match?(CONSTANT) && Object.const_source_location(named)&.first

  def definition(klass, name, here = Dir.pwd)
    path, line = klass.instance_method(name).source_location
    [path.delete_prefix("#{here}#{File::SEPARATOR}"), line]
  end

  def quote(text) = "'#{text.gsub("'") { "'\\''" }}'"
end
