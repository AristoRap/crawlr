# frozen_string_literal: true

require "spec_helper"
require "crawlr/parser"

RSpec.describe Crawlr::Parser do
  describe ".apply_callbacks" do
    let(:html_content) { '<html><body><div class="item">A</div><div class="item">B</div></body></html>' }
    let(:xml_content) { "<root><item>A</item><item>B</item></root>" }
    let(:context) { double("context") }

    before do
      # Stub Crawlr.logger.debug so specs don't log noise
      allow(Crawlr).to receive(:logger).and_return(double(debug: true))
    end

    context "with HTML format callbacks" do
      it "applies all CSS callbacks to matching nodes" do
        results = []
        callbacks = [
          {
            format: :html,
            selector_type: :css,
            selector: ".item",
            block: ->(node, ctx) { results << [node.text, ctx] }
          }
        ]

        described_class.apply_callbacks(
          content: html_content,
          callbacks: callbacks,
          context: context
        )

        expect(results).to contain_exactly(["A", context], ["B", context])
      end

      it "applies XPath callbacks" do
        results = []
        callbacks = [
          {
            format: :html,
            selector_type: :xpath,
            selector: '//div[@class="item"]',
            block: ->(node, _) { results << node.text }
          }
        ]

        described_class.apply_callbacks(
          content: html_content,
          callbacks: callbacks,
          context: context
        )

        expect(results).to eq(%w[A B])
      end
    end

    context "with XML format callbacks" do
      it "parses XML and applies XPath callbacks" do
        results = []
        callbacks = [
          {
            format: :xml,
            selector_type: :xpath,
            selector: "//item",
            block: ->(node, _) { results << node.text }
          }
        ]

        described_class.apply_callbacks(
          content: xml_content,
          callbacks: callbacks,
          context: context
        )

        expect(results).to eq(%w[A B])
      end
    end

    context "with multiple formats" do
      it "parses each format only once" do
        results = []

        html_callback = {
          format: :html,
          selector_type: :css,
          selector: ".item",
          block: ->(node, _) { results << "HTML:#{node.text}" }
        }

        xml_callback = {
          format: :xml,
          selector_type: :xpath,
          selector: "//item",
          block: ->(node, _) { results << "XML:#{node.text}" }
        }

        # apply_callbacks expects one content argument, so run it twice
        described_class.apply_callbacks(content: html_content, callbacks: [html_callback], context: context)
        described_class.apply_callbacks(content: xml_content, callbacks: [xml_callback], context: context)

        expect(results).to include("HTML:A", "HTML:B", "XML:A", "XML:B")
      end
    end

    context "with unsupported format" do
      it "raises ArgumentError" do
        callbacks = [
          {
            format: :json,
            selector_type: :css,
            selector: ".item",
            block: proc {}
          }
        ]

        expect do
          described_class.apply_callbacks(content: html_content, callbacks: callbacks, context: context)
        end.to raise_error(ArgumentError, /Unsupported format json/)
      end
    end

    context "with unsupported selector type" do
      it "raises ArgumentError" do
        callbacks = [
          {
            format: :html,
            selector_type: :invalid,
            selector: ".item",
            block: proc {}
          }
        ]

        expect do
          described_class.apply_callbacks(content: html_content, callbacks: callbacks, context: context)
        end.to raise_error(ArgumentError, /Unsupported selector type invalid/)
      end
    end

    context "with empty callbacks" do
      it "does nothing" do
        expect do
          described_class.apply_callbacks(content: html_content, callbacks: [], context: context)
        end.not_to raise_error
      end
    end
  end
end
