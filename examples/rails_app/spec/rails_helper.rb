ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rspec/rails"

ActiveRecord::Migration.maintain_test_schema!

RSpec.configure do |config|
  config.fixture_paths = [Rails.root.join("test/fixtures")]
  config.global_fixtures = :all
  config.use_transactional_fixtures = true
  config.include ActiveJob::TestHelper
  config.infer_spec_type_from_file_location!
end
