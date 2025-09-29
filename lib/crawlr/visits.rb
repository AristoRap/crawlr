# frozen_string_literal: true

require "concurrent"

module Crawlr
  # Thread-safe visit tracking system for URL deduplication and history management.
  #
  # The Visits class maintains a record of visited URLs to prevent duplicate
  # requests during scraping sessions. It uses concurrent data structures to
  # ensure thread safety in parallel scraping environments and implements
  # memory management through configurable visit limits with automatic cache
  # reset when limits are reached.
  #
  # @example Basic visit tracking
  #   config = Crawlr::Config.new(allow_url_revisit: false, max_visited: 1000)
  #   visits = Crawlr::Visits.new(config)
  #
  #   visits.new?('https://example.com/page1')  #=> true (first time)
  #   visits.register('https://example.com/page1')
  #   visits.new?('https://example.com/page1')  #=> false (already visited)
  #
  # @example With URL revisiting allowed
  #   config = Crawlr::Config.new(allow_url_revisit: true)
  #   visits = Crawlr::Visits.new(config)
  #
  #   visits.new?('https://example.com/page')   #=> true (always allowed)
  #   visits.register('https://example.com/page')
  #   visits.new?('https://example.com/page')   #=> true (revisiting allowed)
  #
  # @example Memory management with limits
  #   config = Crawlr::Config.new(max_visited: 5)
  #   visits = Crawlr::Visits.new(config)
  #
  #   # Add URLs up to limit
  #   (1..5).each do |i|
  #     visits.register("https://example.com/page#{i}")
  #   end
  #
  #   # Next check triggers cache reset
  #   visits.new?('https://example.com/page6')  #=> true (cache was reset)
  #   visits.stats[:visited_count]              #=> 0 (cache cleared)
  #
  # @example Thread-safe parallel scraping
  #   visits = Crawlr::Visits.new(config)
  #
  #   # Safe to use across multiple threads
  #   threads = 10.times.map do |i|
  #     Thread.new do
  #       url = "https://example.com/thread#{i}/page"
  #       if visits.new?(url)
  #         visits.register(url)
  #         scrape_page(url)
  #       end
  #     end
  #   end
  #
  #   threads.each(&:join)
  #
  # @since 0.1.0
  class Visits
    # Initializes a new Visits tracker with the given configuration
    #
    # Creates a thread-safe concurrent map for storing visited URLs and
    # configures behavior based on the provided settings for revisiting
    # and memory management.
    #
    # @param config [Crawlr::Config] Configuration object with visit tracking settings
    # @option config [Boolean] :allow_url_revisit Whether to allow revisiting URLs
    # @option config [Integer] :max_visited Maximum URLs to track before cache reset
    #
    # @example
    #   config = Crawlr::Config.new(
    #     allow_url_revisit: false,
    #     max_visited: 10_000
    #   )
    #   visits = Crawlr::Visits.new(config)
    def initialize(config)
      @config = config
      @visited = Concurrent::Map.new
    end

    # Registers a URL as visited in the tracking system
    #
    # Marks the given URL as visited by storing it in the concurrent map.
    # This method is thread-safe and can be called from multiple threads
    # simultaneously without risk of data corruption.
    #
    # @param url [String] The URL to mark as visited
    # @return [Boolean] Always returns true (the stored value)
    #
    # @example
    #   visits.register('https://example.com/page')
    #   visits.register('https://api.example.com/data?id=123')
    def register(url)
      @visited[url] = true
    end

    # Checks if the visit tracking system is empty
    #
    # Useful for determining if this is the first URL being processed
    # or if the cache has been recently cleared. Can be used to apply
    # different behavior for initial requests (like skipping delays).
    #
    # @return [Boolean] true if no URLs have been visited or cache is empty
    #
    # @example
    #   visits.blank?  #=> true (no visits yet)
    #   visits.register('https://example.com')
    #   visits.blank?  #=> false (has visits)
    def blank?
      @visited.keys.empty?
    end

    # Returns statistics about the visit tracking system
    #
    # Provides metrics about the current state of visit tracking including
    # the number of URLs currently stored and the configured maximum limit.
    # Useful for monitoring memory usage and debugging scraping behavior.
    #
    # @return [Hash<Symbol, Integer>] Statistics hash containing visit metrics
    # @option return [Integer] :visited_count Number of URLs currently tracked
    # @option return [Integer] :max_visited Maximum URLs before cache reset
    #
    # @example
    #   stats = visits.stats
    #   puts "Visited #{stats[:visited_count]} / #{stats[:max_visited]} URLs"
    #
    #   if stats[:visited_count] > stats[:max_visited] * 0.8
    #     puts "Approaching visit limit, cache will reset soon"
    #   end
    def stats
      {
        visited_count: @visited.size,
        max_visited: @config.max_visited
      }
    end

    # Determines if a URL is new (not previously visited)
    #
    # This method implements the core visit deduplication logic including:
    # - Automatic cache reset when maximum visit limit is reached
    # - Configurable URL revisiting behavior
    # - Thread-safe duplicate detection
    # - Logging for debugging and monitoring
    #
    # The method performs memory management by clearing the visited cache
    # when the configured maximum is reached, preventing unbounded memory
    # growth during long-running scraping sessions.
    #
    # @param url [String] URL to check for previous visits
    # @return [Boolean] true if URL is new or revisiting is allowed, false if already visited
    #
    # @example Basic deduplication
    #   visits.new?('https://example.com/page1')  #=> true
    #   visits.register('https://example.com/page1')
    #   visits.new?('https://example.com/page1')  #=> false
    #
    # @example With revisiting enabled
    #   # config.allow_url_revisit = true
    #   visits.new?('https://example.com/page')   #=> true (always)
    #
    # @example Memory limit handling
    #   # When max_visited limit is reached
    #   visits.new?('https://example.com/new')    #=> true (cache reset)
    #   # Previous visits are forgotten after reset
    #
    # @example In parallel scraping context
    #   # Thread-safe checking across multiple workers
    #   if visits.new?(discovered_url)
    #     visits.register(discovered_url)
    #     process_url(discovered_url)
    #   else
    #     skip_duplicate(discovered_url)
    #   end
    def new?(url)
      # Reset if max visited reached
      if @visited.size >= @config.max_visited
        Crawlr.logger.warn "Reached max visited URLs limit (#{@config.max_visited}). Resetting visited cache."
        @visited.clear
      end

      return true if @config.allow_url_revisit
      return true unless @visited.key?(url)

      Crawlr.logger.debug "Already visited #{url}; Skipping"
      false
    end
  end
end
