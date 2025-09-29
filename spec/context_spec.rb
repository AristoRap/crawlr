# frozen_string_literal: true

require "spec_helper"

RSpec.describe Crawlr::Context do
  let(:context) { described_class.new }

  describe "#initialize" do
    it "initializes with default values" do
      expect(context.page_url).to be_nil
      expect(context.base_url).to be_nil
      expect(context.current_depth).to be_zero
    end
  end

  describe "attribute accessors" do
    it "allows setting and getting page_url" do
      context.page_url = "https://example.com/page"
      expect(context.page_url).to eq("https://example.com/page")
    end

    it "allows setting and getting base_url" do
      context.base_url = "https://example.com"
      expect(context.base_url).to eq("https://example.com")
    end

    it "allows setting and getting current_depth" do
      context.current_depth = 5
      expect(context.current_depth).to eq(5)
    end
  end

  describe "state management" do
    it "maintains independent attribute values" do
      context.page_url = "https://example.com/page"
      context.base_url = "https://example.com"
      context.current_depth = 3

      expect(context.page_url).to eq("https://example.com/page")
      expect(context.base_url).to eq("https://example.com")
      expect(context.current_depth).to eq(3)
    end

    it "allows resetting attributes to nil" do
      context.page_url = "https://example.com"
      context.base_url = "https://example.com"
      context.current_depth = 2

      context.page_url = nil
      context.base_url = nil
      context.current_depth = nil

      expect(context.page_url).to be_nil
      expect(context.base_url).to be_nil
      expect(context.current_depth).to be_nil
    end
  end
end
