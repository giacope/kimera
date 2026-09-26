# frozen_string_literal: true

RSpec.describe("kimera run polish features") do
  it "produces identical results with parallel workers" do
    serial = nil
    test_run(cwd: test_sample, args: ["--jobs", "1"]) do |_o, report, _s|
      serial = report["counts"]
    end

    test_run(cwd: test_sample, args: ["--jobs", "4"]) do |_o, report, _s|
      expect(report["counts"]).to(eq(serial))
    end
  end

  it "excludes files matching --exclude" do
    test_run(
      cwd: test_sample,
      args: ["--exclude", "app/services/**/*.rb"]
    ) do |_o, report, _s|
      files = report["results"].map { |r| r["file"] }.uniq
      expect(files).to(all(start_with("app/models")))
    end
  end

  it "suppresses an equivalent mutant via config, adjusting survivors and gate", :aggregate_failures do
    Dir.mktmpdir("kimera-ignore") do |dir|
      config = File.join(dir, "ignore.yml")
      File.write(config, <<~YAML)
        ignore:
          - file: app/models/discount.rb
            line: 33
            label: "> => >="
            reason: known equivalent at the 50 boundary
      YAML

      test_run(
        cwd: test_sample,
        args: ["--config", config, "--max-survivors", "4"]
      ) do |output, report, status|
        counts = report["counts"]
        expect(counts["ignored"]).to(eq(1))
        expect(counts["survived"]).to(eq(4))
        expect(output).to(include("Ignoring 1 mutant(s) marked equivalent"))
        expect(status).to(eq(0))
      end
    end
  end
end
