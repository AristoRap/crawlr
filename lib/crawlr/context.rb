# frozen_string_literal: true

module Crawlr
  # The Context class holds metadata and shared data
  # during a scraping session, such as URLs and crawl depth.
  #
  # It acts like a small key-value store (`@data`) and provides
  # helper methods to manage depth and resolve relative URLs.
  #
  # @example Creating a new context
  #   ctx = Crawlr::Context.new(base_url: "https://example.com")
  #   ctx[:title] = "Home"
  #   ctx.increment_depth
  #   ctx.to_h
  #   # => { base_url: "https://example.com", page_url: nil, current_depth: 1, title: "Home" }
  #
  class Context
    # @return [String, nil] The base URL used for resolving relative links
    # @return [String, nil] The current page URL
    # @return [Integer] The current depth in the crawl hierarchy
    attr_accessor :base_url, :page_url, :current_depth

    # Create a new scraping context.
    #
    # @param [String, nil] base_url The root URL of the crawl
    # @param [String, nil] page_url The current page URL
    # @param [Integer] current_depth The crawl depth (default: 0)
    def initialize(base_url: nil, page_url: nil, current_depth: 0)
      @base_url = base_url
      @page_url = page_url
      @current_depth = current_depth
      @data = {}
    end

    # Retrieve a stored value by key.
    #
    # @param [Symbol, String] key The key to fetch
    # @return [Object, nil] The stored value, or nil if not found
    def [](key)
      @data[key]
    end

    # Assign a value to a key.
    #
    # @param [Symbol, String] key The key to set
    # @param [Object] value The value to store
    # @return [Object] The stored value
    def []=(key, value)
      @data[key] = value
    end

    # Convert the context to a Hash.
    #
    # Includes base_url, page_url, current_depth, and all stored data.
    #
    # @return [Hash] The full context data as a Hash
    def to_h
      {
        base_url: @base_url,
        page_url: @page_url,
        current_depth: @current_depth
      }.merge(@data)
    end

    # Increment the crawl depth by 1.
    #
    # @return [Integer] The updated depth value
    def increment_depth
      @current_depth += 1
    end

    # Resolve a relative URL using the base_url.
    #
    # @param [String] url The relative or absolute URL
    # @return [String] The resolved absolute URL
    def resolve_url(url)
      URI.join(@base_url, url).to_s
    end
  end
end
