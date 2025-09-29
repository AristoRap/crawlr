# frozen_string_literal: true

module Crawlr
  # Event hook management system for scraping lifecycle customization.
  #
  # The Hooks class provides a flexible event-driven system that allows users
  # to register custom behavior at specific points during the scraping process.
  # It supports multiple hooks per event and validates event names to ensure
  # consistency across the framework.
  #
  # @example Basic hook registration
  #   hooks = Crawlr::Hooks.new
  #
  #   hooks.register(:before_visit) do |url, headers|
  #     puts "About to visit: #{url}"
  #     headers['X-Custom'] = 'value'
  #   end
  #
  # @example Multiple hooks for the same event
  #   hooks.register(:after_visit) do |url, response|
  #     log_response_time(url, response)
  #   end
  #
  #   hooks.register(:after_visit) do |url, response|
  #     update_statistics(response.status)
  #   end
  #
  # @example Error handling hooks
  #   hooks.register(:on_error) do |url, error|
  #     error_logger.warn("Failed to scrape #{url}: #{error.message}")
  #     notify_monitoring_system(url, error)
  #   end
  #
  # @author [Your Name]
  # @since 0.1.0
  class Hooks
    # Supported lifecycle events for hook registration
    #
    # @return [Array<Symbol>] Array of valid event names
    # - `:before_visit` - Triggered before making HTTP request
    # - `:after_visit` - Triggered after receiving HTTP response
    # - `:on_error` - Triggered when an error occurs during scraping
    ALLOWED_EVENTS = %i[before_visit after_visit on_error].freeze

    # Initializes a new Hooks instance
    #
    # Creates an empty hook registry with auto-vivifying arrays for each event type.
    #
    # @example
    #   hooks = Crawlr::Hooks.new
    def initialize
      @hooks = Hash.new { |h, k| h[k] = [] }
    end

    # Registers a hook for a specific scraping lifecycle event
    #
    # Hooks are executed in the order they were registered. Multiple hooks
    # can be registered for the same event, and all will be executed when
    # the event is triggered.
    #
    # @param event [Symbol] The lifecycle event to hook into
    # @param block [Proc] The block to execute when the event occurs
    # @yieldparam args [Array] Event-specific arguments passed to the hook
    # @return [void]
    # @raise [ArgumentError] When the event is not in ALLOWED_EVENTS
    # @raise [ArgumentError] When no block is provided
    #
    # @example Before visit hook for request modification
    #   register(:before_visit) do |url, headers|
    #     headers['User-Agent'] = 'Custom Bot 1.0'
    #     headers['Authorization'] = get_auth_token(url)
    #   end
    #
    # @example After visit hook for response processing
    #   register(:after_visit) do |url, response|
    #     response_time = response.headers['X-Response-Time']
    #     metrics.record_response_time(url, response_time)
    #   end
    #
    # @example Error handling hook
    #   register(:on_error) do |url, error|
    #     if error.is_a?(Timeout::Error)
    #       retry_queue.add(url, delay: 30)
    #     end
    #   end
    def register(event, &block)
      raise ArgumentError, "Invalid event #{event}" unless ALLOWED_EVENTS.include?(event)
      raise ArgumentError, "Block required" unless block

      @hooks[event] << block
    end

    # Triggers all registered hooks for a specific event
    #
    # Executes hooks in the order they were registered. If any hook raises
    # an exception, it will be propagated and may prevent subsequent hooks
    # from executing.
    #
    # @param event [Symbol] The event to trigger
    # @param args [Array] Variable arguments to pass to the hook blocks
    # @return [void]
    # @raise [ArgumentError] When the event is not in ALLOWED_EVENTS
    #
    # @example Trigger before_visit hooks
    #   trigger(:before_visit, 'https://example.com', headers_hash)
    #
    # @example Trigger after_visit hooks
    #   trigger(:after_visit, 'https://example.com', response_object)
    #
    # @example Trigger error hooks
    #   trigger(:on_error, 'https://example.com', exception_object)
    def trigger(event, *args)
      raise ArgumentError, "Invalid event #{event}" unless ALLOWED_EVENTS.include?(event)

      @hooks[event].each { |blk| blk.call(*args) }
    end

    # Returns statistics about registered hooks
    #
    # Provides metrics about hook registration for monitoring, debugging,
    # and ensuring expected hooks are properly configured.
    #
    # @return [Hash<Symbol, Object>] Statistics hash containing hook metrics
    # @option return [Integer] :total_hooks Total number of registered hooks across all events
    # @option return [Hash<Symbol, Integer>] :per_event Number of hooks per event type
    #
    # @example
    #   stats = hooks.stats
    #   puts "Total hooks: #{stats[:total_hooks]}"
    #   puts "Before visit hooks: #{stats[:per_event][:before_visit]}"
    #   puts "Error hooks: #{stats[:per_event][:on_error]}"
    def stats
      grouped = @hooks.transform_values(&:size)
      { total_hooks: @hooks.values.flatten.size, per_event: grouped }
    end

    # Clears registered hooks for all events or a specific event
    #
    # Useful for testing, resetting hook configuration, or dynamically
    # changing hook behavior during scraping sessions.
    #
    # @param event [Symbol, nil] Specific event to clear, or nil to clear all
    # @return [void]
    #
    # @example Clear all hooks
    #   hooks.clear
    #
    # @example Clear hooks for specific event
    #   hooks.clear(:before_visit)
    #
    # @example Clear error hooks only
    #   hooks.clear(:on_error)
    def clear(event = nil)
      if event
        @hooks[event].clear
      else
        @hooks.clear
      end
    end
  end
end
