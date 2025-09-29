# frozen_string_literal: true

require "spec_helper"

RSpec.describe Crawlr::Collector do
  let(:collector) { described_class.new }
  let(:mock_response) { double("response", body: "<html><body><h1>Test</h1></body></html>") }

  before do
    collector.visits = Crawlr::Visits.new(collector.config)
  end

  describe "#initialize" do
    it "initializes with default options" do
      expect(collector.http).to be_a(Crawlr::HTTPInterface)
      expect(collector.visits).to be_a(Crawlr::Visits)
    end

    it "sets custom options" do
      custom_collector = described_class.new(
        max_depth: 5,
        random_delay: 2,
        max_parallelism: 10,
        allow_url_revisit: true,
        max_retries: 3
      )

      expect(custom_collector.config.max_depth).to eq(5)
      expect(custom_collector.config.random_delay).to eq(2)
      expect(custom_collector.config.max_parallelism).to eq(10)
      expect(custom_collector.config.allow_url_revisit).to be true
      expect(custom_collector.config.max_retries).to eq(3)
    end
  end

  describe "#on_html" do
    it "adds HTML callback to callbacks array" do
      block = proc { |node, ctx| }
      collector.on_html(:css, "h1", &block)

      callbacks = collector.instance_variable_get(:@callbacks)
      callbacks = callbacks&.all

      expect(callbacks.size).to eq(1)
      expect(callbacks.first).to include(
        format: :html,
        selector_type: :css,
        selector: "h1"
      )
      expect(callbacks.first[:block]).to be_a(Proc)
    end
  end

  describe "#on_xml" do
    it "adds XML callback to callbacks array" do
      block = proc { |node, ctx| }
      collector.on_xml(:xpath, "//item", &block)

      callbacks = collector.instance_variable_get(:@callbacks)
      callbacks = callbacks&.all

      expect(callbacks.size).to eq(1)
      expect(callbacks.first).to include(
        format: :xml,
        selector_type: :xpath,
        selector: "//item"
      )
      expect(callbacks.first[:block]).to be_a(Proc)
    end
  end

  describe "#visit" do
    before do
      allow(collector.http).to receive(:get).and_return(mock_response)
      allow(Crawlr::Parser).to receive(:apply_callbacks)
    end

    it "returns early for nil input" do
      expect(collector.visit(nil)).to be_nil
    end

    it "returns early for empty input" do
      expect(collector.visit("")).to be_nil
    end

    it "handles string input" do
      expect(collector.http).to receive(:get).with("https://example.com")
      collector.visit("https://example.com")
    end

    it "handles array input" do
      urls = ["https://example.com", "https://test.com"]
      # 2 URLs + 2 robots.txt calls per uniq origin
      expect(collector.http).to receive(:get).exactly(4).times
      collector.visit(urls)
    end

    it "handles array input while ignoring robots.txt" do
      collector.config.ignore_robots_txt = true
      urls = ["https://example.com", "https://test.com"]
      # 2 URLs + 2 robots.txt calls per uniq origin
      expect(collector.http).to receive(:get).twice
      collector.visit(urls)
    end

    it "does not fetch when depth exceeds max_depth" do
      collector.config.max_depth = 1
      allow(Crawlr.logger).to receive(:debug)

      expect(collector.http).not_to receive(:get)
      collector.visit("https://example.com", 2)
    end
  end

  describe "#clone" do
    it "creates a new collector with shared state" do
      cloned = collector.clone
      expect(cloned).to be_a(Crawlr::Collector)
      expect(cloned.http).to eq(collector.http)
      expect(cloned.visits).to eq(collector.visits)
      expect(cloned.context).to eq(collector.context)
    end
  end

  describe "#stats" do
    it "returns comprehensive statistics" do
      stats = collector.stats
      expect(stats).to include(:max_depth, :callbacks_count, :allow_url_revisit)
    end
  end

  describe "private methods" do
    describe "#input_to_url_array" do
      it "converts string to array" do
        result = collector.send(:input_to_url_array, "https://example.com")
        expect(result).to be_a(Array)
        expect(result).to contain_exactly("https://example.com")
      end

      it "handles unsupported input type" do
        expect(Crawlr.logger).to receive(:warn).with(/Unsupported input type/)
        result = collector.send(:input_to_url_array, 123)
        expect(result).to be_a(Array)
      end
    end

    describe "#setup_context" do
      it "sets context variables correctly" do
        url = "https://example.com/path"
        depth = 2

        ctx = collector.send(:setup_context, url, depth)

        expect(ctx.page_url).to eq(url)
        expect(ctx.base_url).to eq("https://example.com")
        expect(ctx.current_depth).to eq(depth)
      end
    end
  end
end
