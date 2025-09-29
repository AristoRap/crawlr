# frozen_string_literal: true

require "nokogiri"

module Crawlr
  # Document parsing and callback execution engine.
  #
  # The Parser module provides the core document processing functionality for
  # the Crawlr framework. It efficiently parses HTML and XML content using
  # Nokogiri and executes registered callbacks on matching elements. The module
  # optimizes performance by grouping callbacks by document format to minimize
  # parsing overhead.
  #
  # @example Basic callback execution
  #   content = '<html><body><h1>Title</h1><p>Content</p></body></html>'
  #
  #   callbacks = [
  #     {
  #       format: :html,
  #       selector_type: :css,
  #       selector: 'h1',
  #       block: ->(node, ctx) { ctx.titles << node.text }
  #     }
  #   ]
  #
  #   context = OpenStruct.new(titles: [])
  #   Crawlr::Parser.apply_callbacks(
  #     content: content,
  #     callbacks: callbacks,
  #     context: context
  #   )
  #   puts context.titles #=> ["Title"]
  #
  # @example Mixed HTML and XML parsing
  #   callbacks = [
  #     {
  #       format: :html,
  #       selector_type: :css,
  #       selector: '.product',
  #       block: ->(node, ctx) { process_html_product(node, ctx) }
  #     },
  #     {
  #       format: :xml,
  #       selector_type: :xpath,
  #       selector: '//item[@type="product"]',
  #       block: ->(node, ctx) { process_xml_product(node, ctx) }
  #     }
  #   ]
  #
  #   Crawlr::Parser.apply_callbacks(
  #     content: xml_content,
  #     callbacks: callbacks,
  #     context: scraping_context
  #   )
  #
  # @example Performance optimization with format grouping
  #   # Multiple callbacks for same format - document parsed only once
  #   callbacks = [
  #     { format: :html, selector_type: :css, selector: 'title', block: title_proc },
  #     { format: :html, selector_type: :css, selector: 'meta', block: meta_proc },
  #     { format: :html, selector_type: :xpath, selector: '//a[@href]', block: link_proc }
  #   ]
  #
  #   # HTML content parsed once, all callbacks executed on same document
  #   Crawlr::Parser.apply_callbacks(content: html, callbacks: callbacks, context: ctx)
  #
  # @author [Your Name]
  # @since 0.1.0
  module Parser
    # Applies registered callbacks to parsed document content
    #
    # This method is the main entry point for document processing. It efficiently
    # handles multiple callbacks by grouping them by document format, ensuring
    # that each piece of content is parsed only once per format regardless of
    # how many callbacks are registered for that format.
    #
    # The method performs the following operations:
    # 1. Groups callbacks by document format (:html or :xml)
    # 2. Parses content once per format using appropriate Nokogiri parser
    # 3. Executes all callbacks for each format on the parsed document
    # 4. Extracts matching nodes using CSS or XPath selectors
    # 5. Calls callback blocks with matched nodes and context
    #
    # @param content [String] Raw HTML or XML content to parse
    # @param callbacks [Array<Hash>] Array of callback configuration hashes
    # @param context [Object] Context object passed to callback blocks
    # @option callbacks [Symbol] :format Document format (:html or :xml, defaults to :html)
    # @option callbacks [Symbol] :selector_type Selector type (:css or :xpath)
    # @option callbacks [String] :selector CSS or XPath selector string
    # @option callbacks [Proc] :block Callback block to execute on matching nodes
    # @return [void]
    #
    # @example Single callback execution
    #   callbacks = [{
    #     format: :html,
    #     selector_type: :css,
    #     selector: '.article-title',
    #     block: ->(node, ctx) { ctx.titles << node.text.strip }
    #   }]
    #
    #   Crawlr::Parser.apply_callbacks(
    #     content: html_content,
    #     callbacks: callbacks,
    #     context: context_object
    #   )
    #
    # @example Multiple callbacks with different selectors
    #   callbacks = [
    #     {
    #       format: :html,
    #       selector_type: :css,
    #       selector: 'h1, h2, h3',
    #       block: ->(node, ctx) { ctx.headings << { text: node.text, level: node.name } }
    #     },
    #     {
    #       format: :html,
    #       selector_type: :xpath,
    #       selector: '//a[@href and text()]',
    #       block: ->(node, ctx) { ctx.links << { url: node['href'], text: node.text } }
    #     }
    #   ]
    #
    #   Crawlr::Parser.apply_callbacks(
    #     content: page_html,
    #     callbacks: callbacks,
    #     context: scraping_context
    #   )
    #
    # @example XML feed processing
    #   callbacks = [{
    #     format: :xml,
    #     selector_type: :xpath,
    #     selector: '//item/title',
    #     block: ->(node, ctx) { ctx.feed_titles << node.text }
    #   }]
    #
    #   Crawlr::Parser.apply_callbacks(
    #     content: rss_xml,
    #     callbacks: callbacks,
    #     context: feed_context
    #   )
    #
    # @example Complex data extraction
    #   callbacks = [{
    #     format: :html,
    #     selector_type: :css,
    #     selector: '.product-card',
    #     block: ->(node, ctx) {
    #       product = {
    #         name: node.css('.product-name').text,
    #         price: node.css('.price').text,
    #         image: node.css('img')&.first&.[]('src')
    #       }
    #       ctx.products << product
    #     }
    #   }]
    #
    #   Crawlr::Parser.apply_callbacks(
    #     content: product_page_html,
    #     callbacks: callbacks,
    #     context: product_context
    #   )
    def self.apply_callbacks(content:, callbacks:, context:)
      # Group callbacks by format to minimize parsing
      callbacks_by_format = callbacks.group_by { |cb| cb[:format] || :html }

      callbacks_by_format.each do |format, format_callbacks|
        doc = parse_content(format, content)

        format_callbacks.each do |callback|
          Crawlr.logger.debug "Applying callback: #{callback[:selector_type]} #{callback[:selector]}"
          nodes = extract_nodes(doc, callback[:selector_type], callback[:selector])
          nodes.each { |node| callback[:block].call(node, context) }
        end
      end
    end

    # Parses content using the appropriate Nokogiri parser
    #
    # Creates a Nokogiri document object using either the HTML or XML parser
    # based on the specified format. The HTML parser is more lenient and
    # handles malformed markup better, while the XML parser is stricter and
    # preserves XML-specific features.
    #
    # @param format [Symbol] Document format (:html or :xml)
    # @param content [String] Raw document content to parse
    # @return [Nokogiri::HTML::Document, Nokogiri::XML::Document] Parsed document
    # @raise [ArgumentError] When format is not :html or :xml
    # @api private
    #
    # @example HTML parsing
    #   doc = parse_content(:html, '<html><body>Hello</body></html>')
    #   doc.class #=> Nokogiri::HTML::Document
    #
    # @example XML parsing
    #   doc = parse_content(:xml, '<?xml version="1.0"?><root><item>data</item></root>')
    #   doc.class #=> Nokogiri::XML::Document
    private_class_method def self.parse_content(format, content)
      case format
      when :html then Nokogiri::HTML(content)
      when :xml then Nokogiri::XML(content)
      else raise ArgumentError, "Unsupported format #{format}"
      end
    end

    # Extracts nodes from parsed document using specified selector
    #
    # Executes CSS or XPath selectors against the parsed document to find
    # matching elements. Returns a NodeSet that can be iterated over to
    # process each matching element.
    #
    # @param doc [Nokogiri::HTML::Document, Nokogiri::XML::Document] Parsed document
    # @param selector_type [Symbol] Type of selector (:css or :xpath)
    # @param selector [String] Selector expression to find matching nodes
    # @return [Nokogiri::XML::NodeSet] Collection of matching nodes
    # @raise [ArgumentError] When selector_type is not :css or :xpath
    # @api private
    #
    # @example CSS selector extraction
    #   nodes = extract_nodes(doc, :css, '.product-title')
    #   nodes.each { |node| puts node.text }
    #
    # @example XPath selector extraction
    #   nodes = extract_nodes(doc, :xpath, '//div[@class="content"]//p')
    #   nodes.each { |node| process_paragraph(node) }
    #
    # @example Complex CSS selector
    #   nodes = extract_nodes(doc, :css, 'article > header h1, article > header h2')
    #   # Returns all h1 and h2 elements that are direct children of article headers
    #
    # @example XPath with attributes
    #   nodes = extract_nodes(doc, :xpath, '//a[@href and contains(@class, "external")]')
    #   # Returns all links with href attribute containing "external" class
    private_class_method def self.extract_nodes(doc, selector_type, selector)
      case selector_type
      when :css then doc.css(selector)
      when :xpath then doc.xpath(selector)
      else raise ArgumentError, "Unsupported selector type #{selector_type}"
      end
    end
  end
end
