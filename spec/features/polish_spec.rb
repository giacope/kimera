# frozen_string_literal: true

RSpec.describe("kimera run polish features") do
  it "produces identical results with parallel workers", :aggregate_failures do
    serial, parallel = %w[1 4].map { |jobs| test_outcome(cwd: test_sample, arguments: ["--jobs", jobs]).counts }
    expect(serial).to(include("total" => be_positive))
    expect(parallel).to(eq(serial))
  end

  it "excludes files matching --exclude" do
    test_run(
      cwd: test_sample,
      arguments: ["--exclude", "app/services/**/*.rb"]
    ) do |_o, report, _s|
      files = report["results"].map { |r| r["file"] }.uniq
      expect(files).to(all(start_with("app/models")))
    end
  end

  def ignore_file = <<~YAML
    ignore:
      - file: app/models/discount.rb
        line: 33
        label: "> => >="
        reason: known equivalent at the 50 boundary
  YAML

  def ignoring(config)
    test_outcome(cwd: test_sample, arguments: ["--config", config, "--max-survivors", "4", "--no-count-no-coverage"])
  end

  it "suppresses an equivalent mutant via config, adjusting survivors and gate", :aggregate_failures do
    test_tree({ "ignore.yml" => ignore_file }, "kimera-ignore") do |dir|
      run = ignoring(File.join(dir, "ignore.yml"))
      expect([run.counts.slice("ignored", "survived"), run.status]).to(eq([{ "ignored" => 1, "survived" => 4 }, 0]))
      expect(run.output).to(include("Ignoring 1 mutant(s) marked equivalent"))
    end
  end
end
