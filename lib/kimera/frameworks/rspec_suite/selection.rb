# frozen_string_literal: true

class Kimera::Frameworks::RSpecSuite::Selection < Kimera::Frameworks::Selection
  def file = @tests[@ids.first]&.metadata&.fetch(:rerun_file_path, nil) || @ids.first[/\A(.+?)\[/, 1].to_s

  def plain(out)
    bundle = defined?(Bundler) ? %w[bundle exec] : []
    [*bundle, "rspec", "--format", "json", "--out", out, "--order", "defined", *listed]
  end

  def failed(_output, out)
    examples = JSON.parse(File.read(out, encoding: Encoding::UTF_8)).fetch("examples", [])
    examples.filter_map { |example| example["id"] if example["status"] == "failed" }
  end

  private

  def named(id)
    ex = @tests[id]
    ex ? ex.full_description : id
  end

  def located(id) = { "location" => @tests.fetch(id).location.delete_prefix("./") }

  def known = @tests.keys
end
