#!/usr/bin/env ruby
# frozen_string_literal: true

# Checks each holdout project the way README.md describes:
#   1. plain `rspec` (defined order, as .rspec configures it)
#   2. every example on its own: `rspec spec/FILE:LINE`
#   3. `rspec --order rand:SEED` for each SEED below
#
#   ruby verify.rb [PROJECT ...]   (default: every q* directory here)

require "json"
require "open3"

SEEDS = [1, 42, 1234, 31_337, 65_535, 20_261_014].freeze

def rspec(dir, *args)
  out, st = Open3.capture2e("rspec", *args, chdir: dir)
  [st.success?, out]
end

def count(out) = out[/(\d+) examples?, \d+ failures?/, 1].to_i

root = __dir__
dirs = ARGV.empty? ? Dir[File.join(root, "q*")].select { File.directory?(_1) }.sort : ARGV.map { File.expand_path(_1) }
all_ok = true
dirs.each do |dir|
  name = File.basename(dir)
  ok, out = rspec(dir)
  total = count(out)
  problems = []
  problems << "plain rspec failed:\n#{out}" unless ok

  _, json = rspec(dir, "--dry-run", "--format", "json")
  locations = JSON.parse(json[/\{.*\}/m])["examples"].map { "#{_1['file_path']}:#{_1['line_number']}" }.uniq
  single = 0
  locations.each do |loc|
    lok, lout = rspec(dir, loc)
    single += count(lout)
    problems << "#{loc} failed alone:\n#{lout}" unless lok && count(lout).positive?
  end

  SEEDS.each do |seed|
    sok, sout = rspec(dir, "--order", "rand:#{seed}")
    problems << "seed #{seed} failed:\n#{sout}" unless sok && count(sout) == total
  end

  all_ok &&= problems.empty?
  status = problems.empty? ? "ok" : "FAIL"
  puts format("%-26s %-4s %3d examples; %3d locations run alone (%d example runs); seeds %s",
              name, status, total, locations.size, single, SEEDS.join(","))
  problems.first(2).each { puts "  #{_1.lines.first(15).join('  ')}" }
end
exit(all_ok ? 0 : 1)
