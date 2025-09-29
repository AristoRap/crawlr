# frozen_string_literal: true

module Crawlr
  # Domain filtering and validation class for controlling scraping scope.
  #
  # The Domains class manages which domains are allowed to be scraped by
  # implementing both explicit domain allowlists and glob pattern matching.
  # It provides flexible domain filtering to restrict scraping to specific
  # sites or domain patterns while normalizing domain names for consistent
  # comparison.
  #
  # @example Allow specific domains
  #   config = Crawlr::Config.new(
  #     allowed_domains: ['example.com', 'api.example.com', 'subdomain.site.org']
  #   )
  #   domains = Crawlr::Domains.new(config)
  #
  #   domains.allowed?('https://example.com/page')      #=> true
  #   domains.allowed?('https://www.example.com/page')  #=> true (www. stripped)
  #   domains.allowed?('https://forbidden.com/page')    #=> false
  #
  # @example Use glob patterns for flexible matching
  #   config = Crawlr::Config.new(
  #     domain_glob: ['*.example.com', '*.api.*.com', 'site?.org']
  #   )
  #   domains = Crawlr::Domains.new(config)
  #
  #   domains.allowed?('https://sub.example.com/path')     #=> true
  #   domains.allowed?('https://api.service.com/data')     #=> true
  #   domains.allowed?('https://site1.org/content')        #=> true
  #
  # @example No restrictions (allow all domains)
  #   config = Crawlr::Config.new  # No domain restrictions
  #   domains = Crawlr::Domains.new(config)
  #
  #   domains.allowed?('https://any-site.com')  #=> true
  #
  # @author [Your Name]
  # @since 0.1.0
  class Domains
    # Initializes a new Domains instance with the given configuration
    #
    # @param config [Crawlr::Config] Configuration object containing domain restrictions
    #
    # @example
    #   config = Crawlr::Config.new(allowed_domains: ['site.com'])
    #   domains = Crawlr::Domains.new(config)
    def initialize(config)
      @config = config
      @allowed_domains = extract_allowed_domains(@config.allowed_domains)
      @domain_glob = @config.domain_glob
    end

    # Checks if a URL is allowed based on configured domain restrictions
    #
    # The method performs the following checks in order:
    # 1. If no restrictions are configured, allows all URLs
    # 2. If glob patterns are configured, tests URL against each pattern
    # 3. If explicit domains are configured, checks normalized domain name
    # 4. Logs rejection for debugging purposes
    #
    # @param url [String] The URL to check for domain allowance
    # @return [Boolean] true if the URL's domain is allowed, false otherwise
    #
    # @example With explicit domain allowlist
    #   domains.allowed?('https://example.com/page')        #=> true (if allowed)
    #   domains.allowed?('https://www.example.com/page')    #=> true (www. stripped)
    #   domains.allowed?('https://subdomain.example.com')   #=> false (unless explicitly allowed)
    #
    # @example With glob patterns
    #   # config.domain_glob = ['*.example.com']
    #   domains.allowed?('https://api.example.com')         #=> true
    #   domains.allowed?('https://cdn.example.com/asset')   #=> true
    #   domains.allowed?('https://other.com')               #=> false
    #
    # @example No restrictions
    #   # config.allowed_domains = [], config.domain_glob = []
    #   domains.allowed?('https://any-domain.com')          #=> true
    def allowed?(url)
      return true if @allowed_domains.empty? && @domain_glob.empty?

      unless @domain_glob.empty?
        @domain_glob.each do |glob|
          return true if File.fnmatch?(glob, url)
        end
      end

      uri = URI(url)
      base_name = uri.host.sub("www.", "")
      allowed = @allowed_domains.include?(base_name)

      Crawlr.logger.info("URL not allowed: #{url}") unless allowed
      allowed
    end

    # Returns statistics about the configured domain restrictions
    #
    # Provides metrics about the number of explicitly allowed domains
    # and glob patterns configured for monitoring and debugging purposes.
    #
    # @return [Hash<Symbol, Integer>] Statistics hash containing domain counts
    # @option return [Integer] :allowed_domains Number of explicitly allowed domains
    # @option return [Integer] :domain_glob Number of configured glob patterns
    #
    # @example
    #   stats = domains.domain_stats
    #   puts "Allowing #{stats[:allowed_domains]} explicit domains"
    #   puts "Using #{stats[:domain_glob]} glob patterns"
    def domain_stats
      {
        allowed_domains: @allowed_domains.size,
        domain_glob: @domain_glob.size
      }
    end

    private

    # Extracts and normalizes domain names from the configuration
    #
    # Processes the list of allowed domains by:
    # 1. Handling nil/empty input gracefully
    # 2. Normalizing each domain using base_domain method
    # 3. Removing duplicates from the final list
    #
    # @param domains [Array<String>, nil] List of domain strings to process
    # @return [Array<String>] Normalized, unique list of base domain names
    # @api private
    #
    # @example
    #   extract_allowed_domains(['https://www.example.com', 'api.example.com'])
    #   #=> ['example.com', 'api.example.com']
    def extract_allowed_domains(domains)
      return [] if domains.nil? || domains.empty?

      domains.map { |domain| base_domain(domain) }.uniq
    end

    # Normalizes a domain string to its base form for consistent comparison
    #
    # Performs the following normalization:
    # 1. Parses as URI if it looks like a full URL
    # 2. Ensures path is set to "/" if empty (for valid URI)
    # 3. Extracts hostname and removes "www." prefix
    # 4. Falls back to original string if URI parsing fails
    #
    # @param domain [String] Domain string or URL to normalize
    # @return [String] Normalized base domain name without www prefix
    # @api private
    #
    # @example URL normalization
    #   base_domain('https://www.example.com/path') #=> 'example.com'
    #   base_domain('http://api.site.org')          #=> 'api.site.org'
    #
    # @example Domain name normalization
    #   base_domain('www.example.com')              #=> 'example.com'
    #   base_domain('subdomain.example.com')        #=> 'subdomain.example.com'
    #
    # @example Fallback behavior
    #   base_domain('not-a-valid-uri')              #=> 'not-a-valid-uri'
    def base_domain(domain)
      uri = URI(domain)
      uri.path = "/" if uri.path.empty?
      uri.host ? uri.host.sub("www.", "") : domain
    end
  end
end
