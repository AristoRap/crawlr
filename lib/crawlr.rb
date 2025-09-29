# frozen_string_literal: true

require_relative "crawlr/version"

# A Ruby scraping framework for parsing HTML and XML documents
# @author [Your Name]
# @since 0.1.0
module Crawlr
  class Error < StandardError; end

  class << self
    attr_accessor :logger
  end

  self.logger = Logger.new($stdout, level: Logger::INFO)
end
