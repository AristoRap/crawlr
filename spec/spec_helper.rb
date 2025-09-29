# frozen_string_literal: true

require "rspec"
require "webmock/rspec"
require "nokogiri"
require "logger"

# Configure WebMock
WebMock.disable_net_connect!(allow_localhost: true)

# Mock the modules that are included in Collector
module Crawlr
  class << self
    attr_accessor :logger
  end

  # Mock logger
  self.logger = Logger.new($stdout, level: Logger::DEBUG)
end

# Require your actual classes here
require "crawlr/collector"
require "crawlr/http_interface"
require "crawlr/parser"
require "crawlr/context"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
    expectations.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.warnings = true

  config.default_formatter = "doc" if config.files_to_run.one?

  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed
end
