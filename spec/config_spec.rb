# frozen_string_literal: true

require "spec_helper"
require "crawlr/config"

RSpec.describe Crawlr::Config do
  describe "#initialize" do
    context "with no options" do
      let(:config) { described_class.new }

      it "sets default timeout" do
        expect(config.timeout).to eq(10)
      end

      it "sets default headers" do
        expect(config.headers).to include("User-Agent" => a_string_matching(/Crawlr/))
      end

      it "sets default boolean and numeric values" do
        expect(config.allow_cookies).to be false
        expect(config.max_depth).to eq(0)
        expect(config.random_delay).to eq(0)
        expect(config.max_parallelism).to eq(1)
        expect(config.allow_url_revisit).to be false
        expect(config.max_retries).to eq(0)
        expect(config.max_visited).to eq(10_000)
      end
    end

    context "with custom options" do
      let(:options) do
        {
          timeout: 30,
          default_headers: { "X-Test" => "value" },
          allow_cookies: true,
          max_depth: 5,
          random_delay: 2,
          max_parallelism: 4,
          allow_url_revisit: true,
          max_retries: 3,
          max_visited: 50_000
        }
      end
      let(:config) { described_class.new(options) }

      it "overrides default values" do
        expect(config.timeout).to eq(30)
        expect(config.headers).to include("X-Test" => "value")
        expect(config.allow_cookies).to be true
        expect(config.max_depth).to eq(5)
        expect(config.random_delay).to eq(2)
        expect(config.max_parallelism).to eq(4)
        expect(config.allow_url_revisit).to be true
        expect(config.max_retries).to eq(3)
        expect(config.max_visited).to eq(50_000)
      end
    end
  end

  describe "#to_h" do
    it "returns a hash with all config values" do
      config = described_class.new(timeout: 15, allow_cookies: true)
      hash = config.to_h

      expect(hash).to be_a(Hash)
      expect(hash[:timeout]).to eq(15)
      expect(hash[:allow_cookies]).to be true
      expect(hash[:headers]).to include("User-Agent" => a_string_matching(/Crawlr/))
      expect(hash.keys).to match_array(%i[
                                         timeout headers allowed_domains domain_glob allow_cookies
                                         max_depth random_delay max_parallelism allow_url_revisit
                                         max_retries retry_delay retry_backoff retryable_errors
                                         max_visited proxies proxy_strategy ignore_robots_txt
                                       ])
    end
  end
end
