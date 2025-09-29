# frozen_string_literal: true

require_relative "http_interface"
require_relative "hooks"
require_relative "context"
require_relative "callbacks"
require_relative "parser"
require_relative "config"
require_relative "visits"
require_relative "domains"
require_relative "robots"
require "async/semaphore"

module Crawlr
  # Main orchestrator class that manages scraping sessions.
  #
  # The Collector is the central component of the Crawlr framework, responsible for:
  # - Managing URL visits with configurable depth control
  # - Handling concurrent requests with parallelism limits
  # - Respecting robots.txt and implementing polite crawling delays
  # - Executing registered callbacks on scraped content
  # - Maintaining visit history and domain filtering
  # - Providing hooks for custom behavior during scraping lifecycle
  #
  # @example Basic scraping setup
  #   collector = Crawlr::Collector.new(max_depth: 3, max_parallelism: 5)
  #
  #   collector.on_html(:css, '.product-title') do |node, ctx|
  #     puts "Found: #{node.text} at #{ctx.page_url}"
  #   end
  #
  #   collector.visit('https://example.com')
  #
  # @example Paginated scraping
  #   collector.paginated_visit(
  #     'https://api.example.com/items',
  #     batch_size: 10,
  #     start_page: 1
  #   )
  #
  # @example With hooks and configuration
  #   collector = Crawlr::Collector.new(
  #     max_retries: 3,
  #     random_delay: 2.0,
  #     ignore_robots_txt: false
  #   )
  #
  #   collector.hook(:before_visit) do |url, headers|
  #     puts "About to visit: #{url}"
  #   end
  #
  #   collector.hook(:on_error) do |url, error|
  #     puts "Failed to scrape #{url}: #{error.message}"
  #   end
  #
  # @since 0.1.0
  class Collector
    # @return [Crawlr::Config] The configuration object for this collector
    attr_reader :config

    # @return [Crawlr::Context] The current scraping context
    # @return [Crawlr::HTTPInterface] The HTTP interface for making requests
    # @return [Crawlr::Visits] The visit tracking system
    attr_accessor :context, :http, :visits

    # Initializes a new Collector instance with the given configuration
    #
    # @param options [Hash] Configuration options for the collector
    # @option options [Integer] :max_depth Maximum crawling depth (default: nil for unlimited)
    # @option options [Integer] :max_parallelism Maximum concurrent requests (default: 1)
    # @option options [Float] :random_delay Maximum random delay between requests in seconds
    # @option options [Boolean] :ignore_robots_txt Whether to ignore robots.txt (default: false)
    # @option options [Integer] :max_retries Maximum retry attempts for failed requests
    # @option options [Boolean] :allow_url_revisit Allow revisiting previously scraped URLs
    #
    # @example
    #   collector = Crawlr::Collector.new(
    #     max_depth: 5,
    #     max_parallelism: 3,
    #     random_delay: 1.5
    #   )
    def initialize(options = {})
      @config = Crawlr::Config.new(options)
      @http = Crawlr::HTTPInterface.new(@config)
      @visits = Crawlr::Visits.new(@config)
      @domains = Crawlr::Domains.new(@config)
      @hooks = Crawlr::Hooks.new
      @callbacks = Crawlr::Callbacks.new
      @robots = Crawlr::Robots.new
    end

    # Registers a callback for HTML content using CSS or XPath selectors
    #
    # @param selector_type [Symbol] The type of selector (:css or :xpath)
    # @param selector [String] The selector string to match elements
    # @param block [Proc] The callback block to execute when elements match
    # @yieldparam node [Nokogiri::XML::Node] The matched DOM node
    # @yieldparam ctx [Crawlr::Context] The scraping context
    # @return [void]
    #
    # @example Register CSS selector for HTML
    #   on_html(:css, '.article-title') do |node, ctx|
    #     ctx.titles << node.text.strip
    #   end
    #
    # @example Register XPath selector for HTML
    #   on_html(:xpath, '//a[@class="next-page"]') do |link, ctx|
    #     next_url = URI.join(ctx.base_url, link['href'])
    #     ctx.queue_url(next_url.to_s)
    #   end
    def on_html(selector_type, selector, &block)
      @callbacks.register(:html, selector_type, selector, &block)
    end

    # Registers a callback for XML content using CSS or XPath selectors
    #
    # @param selector_type [Symbol] The type of selector (:css or :xpath)
    # @param selector [String] The selector string to match elements
    # @param block [Proc] The callback block to execute when elements match
    # @yieldparam node [Nokogiri::XML::Node] The matched DOM node
    # @yieldparam ctx [Crawlr::Context] The scraping context
    # @return [void]
    #
    # @example Register XPath selector for XML feeds
    #   on_xml(:xpath, '//item/title') do |title_node, ctx|
    #     ctx.feed_titles << title_node.text
    #   end
    #
    # @example Register CSS selector for XML
    #   on_xml(:css, 'product[price]') do |product, ctx|
    #     ctx.products << parse_product(product)
    #   end
    def on_xml(selector_type, selector, &block)
      @callbacks.register(:xml, selector_type, selector, &block)
    end

    # Visits one or more URLs and processes them according to registered callbacks
    #
    # This method handles the core scraping workflow including:
    # - robots.txt checking (unless disabled)
    # - URL validation and filtering
    # - Concurrent processing with parallelism limits
    # - Depth tracking and limits
    # - Error handling and retry logic
    #
    # @param input [String, Array<String>] Single URL or array of URLs to visit
    # @param current_depth [Integer] Current depth level for recursive crawling
    # @param block [Proc] Optional block to configure the collector before visiting
    # @yieldparam collector [Crawlr::Collector] The collector instance for configuration
    # @return [void]
    #
    # @example Visit a single URL
    #   visit('https://example.com/products')
    #
    # @example Visit multiple URLs
    #   visit(['https://site1.com', 'https://site2.com'])
    #
    # @example Visit with configuration block
    #   visit('https://example.com') do |collector|
    #     collector.on_html(:css, '.product') do |node, ctx|
    #       # Process products
    #     end
    #   end
    #
    # @example Recursive crawling with depth control
    #   visit('https://example.com', 0) # Start at depth 0
    def visit(input, current_depth = 0)
      yield self if block_given?

      urls = normalize_urls(input)
      return if exceeded_max_depth?(urls, current_depth)

      process_robots(urls) unless @config.ignore_robots_txt
      urls = filter_urls(urls)
      return if urls.empty?

      perform_visits(urls, current_depth)
    end

    # Performs paginated scraping by automatically generating page URLs
    #
    # This method is specifically designed for APIs or websites that use
    # query parameter pagination (e.g., ?page=1, ?page=2, etc.). It automatically
    # generates URLs and stops when pages return 404 or too many failures occur.
    #
    # @param url [String] Base URL for pagination
    # @param current_depth [Integer] Starting depth for crawling limits
    # @param query [String] Query parameter name for pagination (default: "page")
    # @param batch_size [Integer] Number of pages to process in parallel batches (default: 5)
    # @param start_page [Integer] Starting page number (default: 1)
    # @param block [Proc] Optional block to configure the collector before visiting
    # @yieldparam collector [Crawlr::Collector] The collector instance for configuration
    # @return [void]
    #
    # @example Basic pagination
    #   paginated_visit('https://api.example.com/items', batch_size: 10)
    #
    # @example Custom query parameter and start page
    #   paginated_visit(
    #     'https://example.com/products',
    #     query: 'p',
    #     start_page: 2,
    #     batch_size: 3
    #   )
    #
    # @example With configuration block
    #   paginated_visit('https://api.site.com/data') do |collector|
    #     collector.on_xml(:css, 'item') do |node, ctx|
    #       process_item(node, ctx)
    #     end
    #   end
    def paginated_visit(url, current_depth: 0, query: "page", batch_size: 5, start_page: 1)
      return unless valid_url?(url)

      yield self if block_given?
      fetch_robots_txt(url) unless @config.ignore_robots_txt
      return unless can_visit?(url, @config.headers)

      pages_to_visit = build_initial_pages(url, query, batch_size, start_page)
      process_page_batches(pages_to_visit, current_depth, batch_size, query)
    end

    # Registers a hook for specific scraping lifecycle events
    #
    # Hooks allow you to execute custom code at specific points during
    # the scraping process, such as before/after visits or on errors.
    #
    # @param event [Symbol] The event to hook into (:before_visit, :after_visit, :on_error)
    # @param block [Proc] The block to execute when the event occurs
    # @yieldparam args [Array] Event-specific arguments passed to the block
    # @return [void]
    #
    # @example Hook before each visit
    #   hook(:before_visit) do |url, headers|
    #     puts "About to visit: #{url}"
    #     headers['Custom-Header'] = 'value'
    #   end
    #
    # @example Hook after each visit
    #   hook(:after_visit) do |url, response|
    #     puts "Visited #{url}, got status: #{response.status}"
    #   end
    #
    # @example Hook for error handling
    #   hook(:on_error) do |url, error|
    #     logger.error "Failed to scrape #{url}: #{error.message}"
    #   end
    def hook(event, &block)
      @hooks.register(event, &block)
    end

    # Creates a clone of the current collector with shared HTTP and visit state
    #
    # This is useful for creating multiple collectors that share the same
    # HTTP connection pool and visit history while having independent
    # callback and hook configurations.
    #
    # @return [Crawlr::Collector] A new collector instance sharing HTTP and visits
    #
    # @example
    #   main_collector = Crawlr::Collector.new(max_parallelism: 10)
    #   product_collector = main_collector.clone
    #
    #   product_collector.on_html(:css, '.product') do |node, ctx|
    #     # Process products with shared visit history
    #   end
    def clone
      new_collector = self.class.new(@config.to_h)
      new_collector.http = @http
      new_collector.visits = @visits

      new_collector
    end

    # Returns comprehensive statistics about the collector's state and activity
    #
    # Provides metrics about configuration, registered hooks/callbacks,
    # visit history, and retry behavior for monitoring and debugging.
    #
    # @return [Hash<Symbol, Object>] Statistics hash containing various metrics
    # @option return [Integer] :max_depth Maximum configured crawling depth
    # @option return [Boolean] :allow_url_revisit Whether URL revisiting is allowed
    # @option return [Integer] :hooks_count Number of registered hooks
    # @option return [Integer] :callbacks_count Number of registered callbacks
    # @option return [Integer] :total_visits Number of URLs visited
    # @option return [Integer] :unique_visits Number of unique URLs visited
    # @option return [Integer] :max_retries Maximum retry attempts (if configured)
    # @option return [Float] :retry_delay Base retry delay in seconds (if configured)
    # @option return [Float] :retry_backoff Retry backoff multiplier (if configured)
    #
    # @example
    #   stats = collector.stats
    #   puts "Visited #{stats[:total_visits]} pages"
    #   puts "Registered #{stats[:callbacks_count]} callbacks"
    def stats
      base = {
        max_depth: @config.max_depth,
        allow_url_revisit: @config.allow_url_revisit
      }

      base.merge!(@hooks.stats)
      base.merge!(@callbacks.stats)
      base.merge!(@visits.stats)
      base.merge!(retry_stats) if @config.max_retries
      base
    end

    private

    # Performs concurrent visits to multiple URLs with parallelism control
    #
    # @param urls [Array<String>] URLs to visit
    # @param current_depth [Integer] Current crawling depth
    # @return [Array<HTTP::Response>, nil] Array of responses or nil if depth exceeded
    # @api private
    def perform_visits(urls, current_depth)
      return if exceeded_max_depth?(urls, current_depth)

      responses = []

      Sync do |parent| # embedded execution
        semaphore = Async::Semaphore.new(@config.max_parallelism || urls.size)

        tasks = urls.map do |url|
          parent.async do
            semaphore.acquire do
              execute_visit(url, current_depth)
            end
          end
        end

        # Wait for all tasks and collect results
        responses = tasks.map(&:wait)
      end

      responses
    end

    # Executes a single URL visit with error handling and context setup
    #
    # @param url [String] URL to visit
    # @param depth [Integer] Current depth level
    # @return [HTTP::Response, nil] HTTP response or nil on error
    # @api private
    def execute_visit(url, depth)
      apply_random_delay(url)

      begin
        response = fetch_response(url)
        raise StandardError unless response

        ctx = setup_context(url, depth)
        scrape_response(response, ctx)
        response
      rescue StandardError => e
        handle_visit_error(url, e)
        nil
      end
    end

    # Fetches a URL with retry logic and error handling
    #
    # @param url [String] URL to fetch
    # @return [HTTP::Response] HTTP response object
    # @raise [StandardError] When all retry attempts are exhausted
    # @api private
    def fetch(url)
      attempt = 0
      begin
        attempt += 1
        @http.get(url) { |url, headers| @hooks.trigger(:before_visit, url, headers) }
      rescue *@config.retryable_errors => e
        if @config.max_retries.positive? && attempt <= @config.max_retries
          delay = calculate_retry_delay(attempt)
          Crawlr.logger.warn "Attempt #{attempt}/#{@config.max_retries + 1} failed for #{url}: #{e.class} - #{e.message}"
          Crawlr.logger.info "Sleeping for #{delay.round(2)}sec before retry"
          sleep(delay)
          retry
        else
          Crawlr.logger.warn "#{@config.max_retries + 1}/#{@config.max_retries + 1} failed attempts for #{url}"
          raise
        end
      end
    end

    # Calculates exponential backoff delay with jitter for retries
    #
    # @param attempt [Integer] Current retry attempt number
    # @return [Float] Calculated delay in seconds
    # @api private
    def calculate_retry_delay(attempt)
      base_delay = @config.retry_delay * (@config.retry_backoff**(attempt - 1))
      jitter = rand(0.1..0.3) * base_delay
      base_delay + jitter
    end

    # Applies a random delay before visiting URLs to be polite
    #
    # @param url [String] URL being visited (for logging)
    # @return [void]
    # @api private
    def apply_random_delay(url)
      return unless @visits.blank?

      time_to_sleep = rand * @config.random_delay
      return unless time_to_sleep.positive?

      Crawlr.logger.debug "Sleeping for #{time_to_sleep.round(2)}sec before visiting #{url}"
      sleep(time_to_sleep)
    end

    # Fetches a URL response and triggers appropriate hooks
    #
    # @param url [String] URL to fetch
    # @return [HTTP::Response, nil] Response object or nil on failure
    # @api private
    def fetch_response(url)
      response = fetch(url)
      @hooks.trigger(:after_visit, url, response)

      return unless response&.body

      @visits.register(url)
      response
    end

    # Applies registered callbacks to scraped response content
    #
    # @param response [HTTP::Response] HTTP response to process
    # @param context [Crawlr::Context] Scraping context
    # @return [void]
    # @api private
    def scrape_response(response, context)
      Crawlr::Parser.apply_callbacks(content: response.body, callbacks: @callbacks.all, context: context)
    end

    # Handles errors that occur during URL visits
    #
    # @param url [String] URL that failed
    # @param error [StandardError] The error that occurred
    # @return [void]
    # @api private
    def handle_visit_error(url, error)
      @hooks.trigger(:on_error, url, error)
      Crawlr.logger.error "Error visiting #{url}: #{error.class} - #{error.message}"
    end

    # Sets up scraping context for a specific URL and depth
    #
    # @param url [String] Current page URL
    # @param depth [Integer] Current crawling depth
    # @return [Crawlr::Context] Configured context object
    # @api private
    def setup_context(url, depth)
      uri = URI(url)
      Crawlr::Context.new(
        page_url: url,
        base_url: uri.origin,
        current_depth: depth
      )
    end

    # Checks if the maximum crawling depth has been exceeded
    #
    # @param input [Array<String>] URLs being processed
    # @param depth [Integer] Current depth level
    # @return [Boolean] true if max depth exceeded
    # @api private
    def exceeded_max_depth?(input, depth)
      if @config.max_depth && depth > @config.max_depth
        Crawlr.logger.debug "Exceeded max depth; Skipping visit to #{input}"
        true
      else
        false
      end
    end

    # Converts various input types to a normalized array of URLs
    #
    # @param input [String, Array<String>] Input URLs
    # @return [Array<String>] Normalized array of unique, non-nil URLs
    # @api private
    def input_to_url_array(input)
      urls = case input
             when String then [input]
             when Array  then input
             else
               Crawlr.logger.warn "Unsupported input type: #{input.class}"
               return []
             end

      urls.compact.uniq
    end

    # Determines if a URL can be visited based on domain, visit history, and robots.txt
    #
    # @param url [String] URL to check
    # @param headers [Hash] HTTP headers for robots.txt checking
    # @return [Boolean] true if URL can be visited
    # @api private
    def can_visit?(url, headers = {})
      return false if url.nil? || url.empty?

      @domains.allowed?(url) &&
        @visits.new?(url) &&
        @robots.allowed?(url, headers["User-Agent"])
    end

    # Validates that a URL is a proper HTTP/HTTPS URL
    #
    # @param url [String] URL to validate
    # @return [Boolean] true if URL is valid HTTP/HTTPS
    # @api private
    def valid_url?(url)
      uri = URI.parse(url)
      uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    rescue URI::InvalidURIError
      false
    end

    # Returns retry-related statistics when retry is configured
    #
    # @return [Hash<Symbol, Object>] Hash containing retry configuration
    # @api private
    def retry_stats
      {
        max_retries: @config.max_retries,
        retry_delay: @config.retry_delay,
        retry_backoff: @config.retry_backoff
      }
    end

    # Fetches robots.txt for a given URL origin
    #
    # @param url [String] URL to get robots.txt for
    # @return [HTTP::Response, nil] robots.txt response or nil on error
    # @api private
    def fetch_robots_txt(url)
      uri = URI.parse(url)
      robots_link = "#{uri.origin}/robots.txt"
      response = fetch_response(robots_link)
      raise StandardError unless response

      response
    rescue StandardError => e
      handle_visit_error(robots_link, e)
      nil
    end

    def normalize_urls(input)
      input_to_url_array(input)
    end

    def process_robots(urls)
      origins = urls.map do |url|
        URI.parse(url).origin
      rescue StandardError
        nil
      end.compact.uniq
      origins.each do |origin|
        next if @robots.exists?(origin)

        response = fetch_robots_txt(origin)
        @robots.parse(origin, response.body) if response&.body
      end
    end

    def filter_urls(urls)
      urls.select { |url| can_visit?(url, @config.headers) }
    end

    def build_initial_pages(url, query, batch_size, start_page)
      max_batch = [@config.max_depth, batch_size].min
      if start_page == 1
        [url] + (max_batch - 1).times.map { |i| "#{url}?#{query}=#{i + 2}" }
      else
        max_batch.times.map { |i| "#{url}?#{query}=#{i + start_page}" }
      end
    end

    def process_page_batches(pages, current_depth, batch_size, query)
      scheduled_depth = current_depth
      max_batch = [@config.max_depth, batch_size].min

      loop do
        break if reached_max_depth?(scheduled_depth)

        batch = next_batch(pages, max_batch)
        break if batch.empty?

        break unless batch_successful?(batch, scheduled_depth)

        scheduled_depth = update_depth(scheduled_depth, max_batch)
        pages = generate_next_pages(batch, scheduled_depth, max_batch, query)
      end
    end

    def valid_batch?(responses, batch_size)
      return false unless responses

      success_count = responses.count { |r| r && r.status != 404 }
      success_count.positive? && success_count >= batch_size / 2
    end

    def reached_max_depth?(depth)
      return false unless @config.max_depth

      depth >= @config.max_depth
    end

    def next_batch(pages, max_batch)
      pages.shift(max_batch)
    end

    def batch_successful?(batch, depth)
      responses = perform_visits(batch, depth)
      return false unless responses

      success_count = responses.count { |r| r && r.status != 404 }
      success_count.positive? && success_count >= batch.size / 2
    end

    def update_depth(current, max_batch)
      current + max_batch
    end

    def generate_next_pages(batch, scheduled_depth, max_batch, query)
      max_batch.times.map { |i| "#{batch.first}?#{query}=#{i + scheduled_depth + 1}" }
    end
  end
end
