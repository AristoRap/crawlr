# frozen_string_literal: true

require "spec_helper"
require "crawlr/callbacks"
RSpec.describe Crawlr::Callbacks do
  subject(:callbacks) { described_class.new }

  describe "#initialize" do
    it "initializes with an empty callbacks array" do
      expect(callbacks.all).to eq([])
    end
  end

  describe "#register" do
    context "with valid inputs" do
      it "registers a callback with css selector" do
        block = proc { |node, ctx| [node, ctx] }
        callbacks.register(:html, :css, ".item", &block)

        expect(callbacks.all.size).to eq(1)
        entry = callbacks.all.first
        expect(entry[:format]).to eq(:html)
        expect(entry[:selector_type]).to eq(:css)
        expect(entry[:selector]).to eq(".item")
        expect(entry[:block]).to be_a(Proc)
      end

      it "registers a callback with xpath selector" do
        block = proc { |node, ctx| [node, ctx] }
        callbacks.register(:xml, :xpath, "//div", &block)

        entry = callbacks.all.first
        expect(entry[:selector_type]).to eq(:xpath)
        expect(entry[:selector]).to eq("//div")
      end
    end

    context "with invalid format" do
      it "raises an ArgumentError for unsupported format" do
        expect do
          callbacks.register(:json, :css, ".item") {}
        end.to raise_error(ArgumentError, /Unsupported format: json/)
      end
    end

    context "with invalid selector type" do
      it "raises an ArgumentError for unsupported selector type" do
        expect do
          callbacks.register(:html, :invalid, ".item") {}
        end.to raise_error(ArgumentError, /Unsupported selector type: invalid/)
      end
    end
  end

  describe "#register" do
    it "adds a callback to the list" do
      block = proc { |node, ctx| [node, ctx] }
      callbacks.register(:html, :css, ".item", &block)

      expect(callbacks.all.size).to eq(1)
      entry = callbacks.all.first
      expect(entry[:format]).to eq(:html)
      expect(entry[:selector_type]).to eq(:css)
      expect(entry[:selector]).to eq(".item")

      # Ensure the block can be called
      node = double("node")
      ctx = double("ctx")
      expect(entry[:block].call(node, ctx)).to eq([node, ctx])
    end
  end

  describe "#stats" do
    it "returns a hash with callback count" do
      expect(callbacks.stats).to eq(callbacks_count: 0)

      callbacks.register(:html, :css, ".item") {}
      expect(callbacks.stats).to eq(callbacks_count: 1)
    end
  end

  describe "#clear" do
    it "removes all callbacks" do
      callbacks.register(:html, :css, ".item") {}
      expect(callbacks.all.size).to eq(1)

      callbacks.clear
      expect(callbacks.all).to be_empty
    end
  end

  describe "private #parse_input" do
    it "parses css input correctly" do
      result = callbacks.send(:parse_input, "css@.item")
      expect(result).to eq([:css, ".item"])
    end

    it "parses xpath input correctly" do
      result = callbacks.send(:parse_input, "xpath@//div")
      expect(result).to eq([:xpath, "//div"])
    end

    it "raises ArgumentError for unsupported input" do
      expect do
        callbacks.send(:parse_input, "bad@.item")
      end.to raise_error(ArgumentError, /Unsupported input format/)
    end
  end
end
