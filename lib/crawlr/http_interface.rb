# frozen_string_literal: true

require "async"
require "async/timeout"
require "async/http/internet"
require "http/cookie_jar"

module Crawlr
  # Handles fetching documents via async HTTP with proxy and cookie support.
  #
  # The HTTPInterface class provides a high-level async HTTP client specifically
  # designed for web scraping. It supports proxy rotation, cookie management,
  # configurable timeouts, and transforms raw HTTP responses into a simplified
  # response structure suitable for content processing.
  #
  # @example Basic HTTP fetching
  #   config = Crawlr::Config.new(timeout: 10)
  #   http = Crawlr::HTTPInterface.new(config)
  #
  #   response = http.get('https://example.com')
  #   puts response.status  #=> 200
  #   puts response.body    #=> HTML content
  #
  # @example With cookie support
  #   config = Crawlr::Config.new(allow_cookies: true)
  #   http = Crawlr::HTTPInterface.new(config)
  #
  #   # Cookies are automatically managed across requests
  #   login_response = http.get('https://site.com/login')
  #   profile_response = http.get('https://site.com/profile')  # Uses login cookies
  #
  # @example With proxy rotation
  #   config = Crawlr::Config.new(
  #     proxies: ['http://proxy1:8080', 'socks5://proxy2:1080'],
  #     proxy_strategy: :round_robin
  #   )
  #   http = Crawlr::HTTPInterface.new(config)
  #
  #   response = http.get('https://example.com')  # Uses proxy1
  #   response = http.get('https://example.com')  # Uses proxy2
  #
  # @example With request hooks
  #   response = http.get('https://api.example.com') do |url, headers|
  #     headers['Authorization'] = "Bearer #{get_token()}"
  #     headers['X-Request-ID'] = SecureRandom.uuid
  #   end
  #
  # @author [Your Name]
  # @since 0.1.0
  class HTTPInterface
    # Simplified HTTP response structure for internal use
    #
    # @!attribute [r] url
    #   @return [String] The requested URL
    # @!attribute [r] status
    #   @return [Integer] HTTP status code
    # @!attribute [r] headers
    #   @return [Hash] HTTP response headers
    # @!attribute [r] version
    #   @return [String] HTTP protocol version
    # @!attribute [r] body
    #   @return [String, nil] Response body content
    Response = Struct.new(:url, :status, :headers, :version, :body)

    # @return [Crawlr::Config] Configuration object containing HTTP settings
    attr_reader :config

    # Initializes a new HTTPInterface with the given configuration
    #
    # Sets up cookie management (if enabled) and proxy rotation state.
    # The cookie jar persists across all requests made by this interface instance.
    #
    # @param config [Crawlr::Config] Configuration object with HTTP settings
    # @option config [Boolean] :allow_cookies Enable cookie jar management
    # @option config [Array<String>] :proxies List of proxy URLs
    # @option config [Symbol] :proxy_strategy Proxy selection strategy (:round_robin, :random)
    # @option config [Integer] :timeout Request timeout in seconds
    # @option config [Hash] :headers Default headers for all requests
    #
    # @example
    #   config = Crawlr::Config.new(
    #     allow_cookies: true,
    #     timeout: 15,
    #     proxies: ['http://proxy.example.com:8080']
    #   )
    #   http = Crawlr::HTTPInterface.new(config)
    def initialize(config)
      @config = config
      @cookie_jar = @config.allow_cookies ? HTTP::CookieJar.new : nil
      @proxy_index = 0
    end

    # Performs an HTTP GET request with full async support and cookie management
    #
    # This method handles the complete HTTP request lifecycle including:
    # - Proxy selection and connection setup
    # - Cookie retrieval and attachment
    # - Request header customization via block
    # - Async execution with timeout handling
    # - Response cookie parsing and storage
    # - Resource cleanup and connection closing
    #
    # @param url [String] The URL to fetch
    # @param block [Proc] Optional block for request customization
    # @yieldparam url [String] The URL being requested
    # @yieldparam headers [Hash] Mutable headers hash for customization
    # @return [HTTPInterface::Response] Simplified response object
    # @raise [Async::TimeoutError] When request exceeds configured timeout
    # @raise [URI::InvalidURIError] When URL is malformed
    # @raise [StandardError] For other HTTP-related errors
    #
    # @example Basic GET request
    #   response = http.get('https://example.com/api/data')
    #   if response.status == 200
    #     data = JSON.parse(response.body)
    #   end
    #
    # @example With custom headers
    #   response = http.get('https://api.service.com/endpoint') do |url, headers|
    #     headers['Accept'] = 'application/json'
    #     headers['X-API-Key'] = ENV['API_KEY']
    #     headers['User-Agent'] = 'MyBot/1.0'
    #   end
    #
    # @example With authentication
    #   response = http.get('https://secure.site.com/data') do |url, headers|
    #     token = authenticate_user(url)
    #     headers['Authorization'] = "Bearer #{token}"
    #   end
    #
    # @example Error handling
    #   begin
    #     response = http.get('https://unreliable.com/data')
    #   rescue Async::TimeoutError
    #     puts "Request timed out"
    #   rescue StandardError => e
    #     puts "Request failed: #{e.message}"
    #   end
    def get(url)
      Crawlr.logger.debug "Fetching #{url}"

      uri = URI.parse(url)
      proxy_url = next_proxy
      internet = build_internet_connection(proxy_url)

      request_headers = @config.headers.dup

      if @config.allow_cookies
        cookie_header = HTTP::Cookie.cookie_value(@cookie_jar.cookies(uri))
        request_headers["cookie"] = cookie_header if cookie_header && !cookie_header.empty?
      end

      yield(url, request_headers) if block_given?

      raw_response = nil
      begin
        Sync do |task|
          raw_response = task.with_timeout(@config.timeout) do
            internet.get(url, request_headers)
          end
        end

        parse_and_set_cookies(uri, raw_response) if @config.allow_cookies && raw_response
        make_response_struct(url, raw_response)
      rescue Async::TimeoutError
        Crawlr.logger.warn "Timeout fetching #{url} after #{@config.timeout}sec"
        raise
      ensure
        raw_response&.close
        internet&.close
        Crawlr.logger.debug "Done fetching #{url}"
      end
    end

    private

    # Builds an async HTTP connection with optional proxy support
    #
    # Creates either a direct internet connection or a proxied connection
    # based on the provided proxy URL. Supports HTTP and SOCKS5 proxies.
    #
    # @param proxy [String, nil] Proxy URL or nil for direct connection
    # @return [Async::HTTP::Internet, Async::HTTP::Client] HTTP connection object
    # @raise [URI::InvalidURIError] When proxy URL is malformed
    # @api private
    #
    # @example Direct connection
    #   connection = build_internet_connection(nil)
    #
    # @example HTTP proxy
    #   connection = build_internet_connection('http://proxy.example.com:8080')
    #
    # @example SOCKS proxy with authentication
    #   connection = build_internet_connection('socks5://user:pass@proxy.example.com:1080')
    def build_internet_connection(proxy = nil)
      if proxy
        # Expected format: "http://user:pass@host:port" or "socks5://host:port"
        uri = URI.parse(proxy)
        Crawlr.logger.debug "Using proxy: #{uri}"
        # Async::HTTP::Proxy requires target endpoint
        endpoint = Async::HTTP::Endpoint.parse(uri.to_s)
        Async::HTTP::Client.new(endpoint)
      else
        Async::HTTP::Internet.new
      end
    end

    # Selects the next proxy according to the configured strategy
    #
    # Implements proxy rotation strategies to distribute requests across
    # multiple proxy servers. Maintains state for round-robin selection.
    #
    # @return [String, nil] Next proxy URL or nil if no proxies configured
    # @raise [StandardError] When proxy_strategy is unknown
    # @api private
    #
    # @example Round-robin selection
    #   proxy = next_proxy  # Returns first proxy
    #   proxy = next_proxy  # Returns second proxy
    #   proxy = next_proxy  # Wraps back to first proxy
    #
    # @example Random selection
    #   # config.proxy_strategy = :random
    #   proxy = next_proxy  # Returns random proxy from list
    def next_proxy
      return nil if @config.proxies.empty?

      case @config.proxy_strategy
      when :round_robin
        proxy = @config.proxies[@proxy_index % @config.proxies.size]
        @proxy_index += 1
        proxy
      when :random
        @config.proxies.sample
      else
        raise "Unknown proxy strategy: #{@config.proxy_strategy}"
      end
    end

    # Creates a simplified response struct from the raw HTTP response
    #
    # Transforms the async-http response object into a simplified structure
    # that's easier to work with in the scraping framework. Safely handles
    # body reading with error recovery.
    #
    # @param url [String] The original request URL
    # @param response [Async::HTTP::Response] Raw async-http response object
    # @return [HTTPInterface::Response] Simplified response struct
    # @api private
    def make_response_struct(url, response)
      body = begin
        response.read
      rescue StandardError
        nil
      end

      Response.new(url, response.status, response.headers, response.version, body)
    end

    # Parses and stores cookies from HTTP response headers
    #
    # Extracts Set-Cookie headers from the response and adds them to the
    # internal cookie jar for use in subsequent requests. Handles multiple
    # cookies and logs cookie information for debugging.
    #
    # @param uri [URI] The request URI for cookie domain/path context
    # @param response [Async::HTTP::Response] HTTP response containing cookies
    # @return [void]
    # @api private
    #
    # @example Cookie processing
    #   # Response contains: Set-Cookie: session_id=abc123; Domain=.example.com; Path=/
    #   parse_and_set_cookies(uri, response)
    #   # Cookie is stored and will be sent with future requests to example.com
    def parse_and_set_cookies(uri, response)
      set_cookies = response.headers["set-cookie"]
      Array(set_cookies).each do |set_cookie|
        HTTP::Cookie.parse(set_cookie.to_s, uri).each do |cookie|
          @cookie_jar.add(cookie)
          Crawlr.logger.debug "Received cookie: #{cookie.name}=#{cookie.value};" \
                              " domain=#{cookie.domain}, path=#{cookie.path}"
        end
      end
    end
  end
end
