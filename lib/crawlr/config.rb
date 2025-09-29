# frozen_string_literal: true

module Crawlr
  # Configuration management class for Crawlr scraping sessions.
  #
  # The Config class centralizes all configuration options for the Crawlr framework,
  # providing sensible defaults while allowing extensive customization of scraping
  # behavior, networking settings, error handling, and crawling policies.
  #
  # @example Basic configuration
  #   config = Crawlr::Config.new(
  #     timeout: 15,
  #     max_depth: 3,
  #     max_parallelism: 5
  #   )
  #
  # @example Advanced configuration with domain filtering and retries
  #   config = Crawlr::Config.new(
  #     allowed_domains: ['example.com', 'api.example.com'],
  #     max_retries: 3,
  #     retry_delay: 2.0,
  #     retry_backoff: 1.5,
  #     random_delay: 1.0,
  #     allow_cookies: true,
  #     ignore_robots_txt: false
  #   )
  #
  # @example Proxy configuration
  #   config = Crawlr::Config.new(
  #     proxies: ['proxy1.com:8080', 'proxy2.com:8080'],
  #     proxy_strategy: :random,
  #     max_parallelism: 10
  #   )
  #
  # @since 0.1.0
  class Config
    # @return [Integer] HTTP request timeout in seconds
    # @return [Hash<String, String>] Default HTTP headers for all requests
    # @return [Array<String>] Glob patterns for allowed domains
    # @return [Array<String>] Explicit list of allowed domains
    # @return [Boolean] Whether to enable cookie handling
    # @return [Integer] Maximum crawling depth (0 for unlimited)
    # @return [Float] Maximum random delay between requests in seconds
    # @return [Integer] Maximum number of concurrent requests
    # @return [Boolean] Whether to allow revisiting previously scraped URLs
    # @return [Integer, nil] Maximum number of retry attempts (nil to disable)
    # @return [Float] Base delay between retry attempts in seconds
    # @return [Float] Exponential backoff multiplier for retry delays
    # @return [Array<Class>] List of exception classes that trigger retries
    # @return [Integer] Maximum number of URLs to track in visit history
    # @return [Array<String>] List of proxy server addresses
    # @return [Symbol] Strategy for selecting proxies (:round_robin, :random)
    # @return [Boolean] Whether to ignore robots.txt restrictions
    attr_accessor :timeout, :headers, :domain_glob, :allowed_domains, :allow_cookies,
                  :max_depth, :random_delay, :max_parallelism, :allow_url_revisit,
                  :max_retries, :retry_delay, :retry_backoff, :retryable_errors,
                  :max_visited, :proxies, :proxy_strategy, :ignore_robots_txt

    # Initializes a new Config instance with the provided options
    #
    # @param options [Hash] Configuration options hash
    # @option options [Integer] :timeout (10) HTTP request timeout in seconds
    # @option options [Hash<String, String>] :default_headers Default HTTP headers
    # @option options [Array<String>] :allowed_domains ([]) Explicit list of allowed domains
    # @option options [Array<String>] :domain_glob ([]) Glob patterns for domain filtering
    # @option options [Boolean] :allow_cookies (false) Enable cookie handling
    # @option options [Integer] :max_depth (0) Maximum crawling depth (0 = unlimited)
    # @option options [Float] :random_delay (0) Maximum random delay between requests
    # @option options [Integer] :max_parallelism (1) Maximum concurrent requests
    # @option options [Boolean] :allow_url_revisit (false) Allow revisiting URLs
    # @option options [Integer] :max_retries (0) Maximum retry attempts (0 = disabled)
    # @option options [Float] :retry_delay (1.0) Base retry delay in seconds
    # @option options [Float] :retry_backoff (2.0) Exponential backoff multiplier
    # @option options [Array<Class>] :retryable_errors Custom list of retryable exceptions
    # @option options [Integer] :max_visited (10000) Maximum URLs to track in history
    # @option options [Array<String>] :proxies ([]) List of proxy servers
    # @option options [Symbol] :proxy_strategy (:round_robin) Proxy selection strategy
    # @option options [Boolean] :ignore_robots_txt (false) Ignore robots.txt restrictions
    #
    # @raise [StandardError] When both :allowed_domains and :domain_glob are specified
    #
    # @example Minimal configuration
    #   config = Crawlr::Config.new
    #
    # @example Timeout and parallelism configuration
    #   config = Crawlr::Config.new(
    #     timeout: 30,
    #     max_parallelism: 8
    #   )
    #
    # @example Domain filtering with explicit domains
    #   config = Crawlr::Config.new(
    #     allowed_domains: ['site1.com', 'api.site1.com']
    #   )
    #
    # @example Domain filtering with glob patterns
    #   config = Crawlr::Config.new(
    #     domain_glob: ['*.example.com', '*.api.example.com']
    #   )
    #
    # @example Retry configuration with custom errors
    #   config = Crawlr::Config.new(
    #     max_retries: 5,
    #     retry_delay: 0.5,
    #     retry_backoff: 1.5,
    #     retryable_errors: [Timeout::Error, Net::ReadTimeout]
    #   )
    def initialize(options = {})
      initialize_domain_settings(options)
      initialize_parallelism_settings(options)
      initialize_throttle_settings(options)
      initialize_http_settings(options)
      initialize_retry_settings(options)
      initialize_visit_settings(options)
      initialize_proxy_settings(options)
      initialize_robots_settings(options)

      validate
    end

    # Converts the configuration to a hash representation
    #
    # This method is useful for serialization, debugging, or creating
    # new Config instances with the same settings.
    #
    # @return [Hash<Symbol, Object>] Hash containing all configuration values
    #
    # @example
    #   config = Crawlr::Config.new(timeout: 15, max_depth: 3)
    #   hash = config.to_h
    #   new_config = Crawlr::Config.new(hash)
    #
    # @example Inspect configuration
    #   puts config.to_h.inspect
    def to_h
      attrs = %i[
        timeout headers allowed_domains domain_glob allow_cookies max_depth
        random_delay max_parallelism allow_url_revisit max_retries retry_delay
        retry_backoff retryable_errors max_visited proxies proxy_strategy
        ignore_robots_txt
      ]

      attrs.each_with_object({}) { |name, hash| hash[name] = instance_variable_get("@#{name}") }
    end

    private

    def initialize_domain_settings(options)
      @allowed_domains = Array(options[:allowed_domains])
      @domain_glob     = Array(options[:domain_glob])
    end

    def initialize_parallelism_settings(options)
      @max_parallelism = options.fetch(:max_parallelism, 1)
    end

    def initialize_throttle_settings(options)
      @random_delay = options.fetch(:random_delay, 0)
    end

    def initialize_http_settings(options)
      @timeout      = options.fetch(:timeout, 10)
      @headers      = options[:default_headers] || default_headers
      @allow_cookies = options.fetch(:allow_cookies, false)
      @max_depth = options.fetch(:max_depth, 0)
    end

    def initialize_retry_settings(options)
      @max_retries       = options[:max_retries]&.positive? ? options[:max_retries] : 0
      @retry_delay       = options.fetch(:retry_delay, 1.0)
      @retry_backoff     = options.fetch(:retry_backoff, 2.0)
      @retryable_errors  = options[:retryable_errors] || default_retryable_errors
    end

    def initialize_visit_settings(options)
      @allow_url_revisit = options.fetch(:allow_url_revisit, false)
      @max_visited       = options.fetch(:max_visited, 10_000)
    end

    def initialize_proxy_settings(options)
      @proxies        = Array(options[:proxies])
      @proxy_strategy = options.fetch(:proxy_strategy, :round_robin)
    end

    def initialize_robots_settings(options)
      @ignore_robots_txt = options.fetch(:ignore_robots_txt, false)
    end

    # Returns the default HTTP headers for requests
    #
    # @return [Hash<String, String>] Default headers with User-Agent
    # @api private
    def default_headers
      {
        "User-Agent" => "Crawlr/#{Crawlr::VERSION}"
      }
    end

    # Returns the default list of exceptions that should trigger retries
    #
    # These exceptions typically represent temporary network issues
    # that may resolve on subsequent attempts.
    #
    # @return [Array<Class>] Array of exception classes for retry logic
    # @api private
    def default_retryable_errors
      [
        Async::TimeoutError,
        Errno::ECONNREFUSED,
        Errno::ECONNRESET,
        Errno::EHOSTUNREACH,
        Errno::ENETUNREACH,
        SocketError
      ]
    end

    # Validates the configuration for conflicting options
    #
    # Ensures that mutually exclusive configuration options are not
    # specified simultaneously, which would create ambiguous behavior.
    #
    # @return [void]
    # @raise [StandardError] When both allowed_domains and domain_glob are specified
    # @api private
    def validate
      return unless !@allowed_domains.empty? && !@domain_glob.empty?

      raise "Cannot specify both allowed_domains and domain_glob"
    end
  end
end
