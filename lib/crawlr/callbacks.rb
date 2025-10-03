# frozen_string_literal: true

module Crawlr
  # Manages callback registration and execution for document scraping operations.
  #
  # The Callbacks class provides a centralized way to register and manage
  # callbacks that process specific nodes in HTML or XML documents using
  # CSS or XPath selectors.
  #
  # @example Basic usage
  #   callbacks = Crawlr::Callbacks.new
  #   callbacks.register(:html, :css, '.title') do |node, context|
  #     puts node.text
  #   end
  #
  # @example Using XPath selectors
  #   callbacks.register(:xml, :xpath, '//item[@id]') do |node, context|
  #     process_item(node, context)
  #   end
  #
  # @since 0.1.0
  class Callbacks
    # Supported document formats for scraping
    # @return [Array<Symbol>] Array of allowed format symbols
    ALLOWED_FORMATS = %i[html xml].freeze

    # Supported selector types for element selection
    # @return [Array<Symbol>] Array of allowed selector type symbols
    ALLOWED_SELECTOR_TYPES = %i[css xpath].freeze

    # Initializes a new Callbacks instance
    #
    # @example
    #   callbacks = Crawlr::Callbacks.new
    def initialize
      @callbacks = []
    end

    # Returns a copy of all registered callbacks
    #
    # @return [Array<Hash>] Array of callback hashes containing format, selector_type, selector, and block
    # @example
    #   callbacks = instance.all
    #   puts callbacks.length #=> 3
    def all
      @callbacks.dup
    end

    # Registers a new callback for processing matching nodes
    #
    # @param format [Symbol] The document format (:html or :xml)
    # @param selector_type [Symbol] The selector type (:css or :xpath)
    # @param selector [String] The selector string to match elements
    # @param block [Proc] The callback block to execute when elements match
    # @yieldparam node [Object] The matched DOM node
    # @yieldparam ctx [Object] The scraping context object
    # @return [void]
    # @raise [ArgumentError] When format or selector_type is not supported
    #
    # @example Register a CSS selector callback
    #   register(:html, :css, '.product-title') do |node, ctx|
    #     ctx.titles << node.text.strip
    #   end
    #
    # @example Register an XPath selector callback
    #   register(:xml, :xpath, '//item[@price > 100]') do |node, ctx|
    #     ctx.expensive_items << parse_item(node)
    #   end
    def register(format, selector_type, selector, &block)
      validate_registration(format, selector_type)
      @callbacks << {
        format: format,
        selector_type: selector_type,
        selector: selector,
        block: ->(node, ctx) { block.call(node, ctx) }
      }
    end

    # Returns basic statistics about registered callbacks
    #
    # @return [Hash<Symbol, Integer>] Hash containing callback statistics
    # @example
    #   stats = instance.stats
    #   puts stats[:callbacks_count] #=> 5
    def stats
      { callbacks_count: @callbacks.size }
    end

    # Clears all registered callbacks
    #
    # @return [Array] Empty callbacks array
    # @example
    #   instance.clear
    #   puts instance.stats[:callbacks_count] #=> 0
    def clear
      @callbacks.clear
    end

    private

    # Validates that the format and selector_type are supported
    #
    # @param format [Symbol] The document format to validate
    # @param selector_type [Symbol] The selector type to validate
    # @return [void]
    # @raise [ArgumentError] When format is not in ALLOWED_FORMATS
    # @raise [ArgumentError] When selector_type is not in ALLOWED_SELECTOR_TYPES
    # @api private
    def validate_registration(format, selector_type)
      raise ArgumentError, "Unsupported format: #{format}" unless ALLOWED_FORMATS.include?(format)
      return if ALLOWED_SELECTOR_TYPES.include?(selector_type)

      raise ArgumentError, "Unsupported selector type: #{selector_type}"
    end

    # Alternative registration method using formatted input strings
    #
    # @param format [Symbol] The document format (:html or :xml)
    # @param input [String] Formatted input string (e.g., "css@.selector" or "xpath@//element")
    # @param block [Proc] The callback block to execute when elements match
    # @yieldparam node [Object] The matched DOM node
    # @yieldparam ctx [Object] The scraping context object
    # @return [void]
    # @raise [ArgumentError] When format is not supported
    # @raise [ArgumentError] When selector_type parsed from input is not supported
    # @raise [ArgumentError] When input format is invalid
    # @api private
    #
    # @example Using CSS selector input format
    #   register_from_input(:html, "css@.product-name") do |node, ctx|
    #     # Process node
    #   end
    #
    # @example Using XPath selector input format
    #   register_from_input(:xml, "xpath@//item[@id]") do |node, ctx|
    #     # Process node
    #   end
    #
    # @note This is a potential shorthand method that may be exposed in future versions
    def register_from_input(format, input, &block)
      raise ArgumentError, "Unsupported format: #{format}" unless ALLOWED_FORMATS.include?(format)

      selector_type, selector = parse_input(input)
      raise ArgumentError, "Unsupported selector type: #{selector_type}" unless ALLOWED_SELECTOR_TYPES.include?(selector_type)

      register(format, selector_type, selector, &block)
    end

    # Parses formatted input strings to extract selector type and selector
    #
    # @param input [String] Formatted input string with type prefix
    # @return [Array<(Symbol, String)>] Tuple of [selector_type, selector]
    # @raise [ArgumentError] When input format doesn't match expected patterns
    # @api private
    #
    # @example Parse CSS selector input
    #   parse_input("css@.my-class") #=> [:css, ".my-class"]
    #
    # @example Parse XPath selector input
    #   parse_input("xpath@//div[@id='main']") #=> [:xpath, "//div[@id='main']"]
    def parse_input(input)
      if input.start_with?("css@")
        selector_type = :css
        selector = input[4..]
      elsif input.start_with?("xpath@")
        selector_type = :xpath
        selector = input[6..]
      else
        raise ArgumentError, "Unsupported input format: #{input}"
      end

      [selector_type, selector]
    end
  end
end
