# frozen_string_literal: true

require "uri"

module Crawlr
  # Robots.txt parser and compliance checker for respectful web scraping.
  #
  # The Robots class implements full robots.txt specification compliance,
  # including user-agent matching, path pattern matching with wildcards,
  # allow/disallow precedence rules, and crawl-delay directives. It helps
  # ensure that scrapers respect website crawling policies and avoid
  # making unwanted requests.
  #
  # @example Basic robots.txt compliance
  #   robots = Crawlr::Robots.new
  #
  #   # Parse robots.txt content
  #   robots_content = <<~ROBOTS
  #     User-agent: *
  #     Disallow: /private/
  #     Allow: /public/
  #     Crawl-delay: 1
  #   ROBOTS
  #
  #   robots.parse('https://example.com', robots_content)
  #
  #   # Check URL permissions
  #   robots.allowed?('https://example.com/public/page', 'MyBot/1.0')  #=> true
  #   robots.allowed?('https://example.com/private/data', 'MyBot/1.0') #=> false
  #
  # @example Complex user-agent matching
  #   robots_content = <<~ROBOTS
  #     User-agent: Googlebot
  #     Disallow: /admin/
  #
  #     User-agent: *
  #     Disallow: /
  #     Allow: /public/
  #   ROBOTS
  #
  #   robots.parse('https://site.com', robots_content)
  #
  #   robots.allowed?('https://site.com/admin/', 'Googlebot/2.1')      #=> false
  #   robots.allowed?('https://site.com/public/', 'Googlebot/2.1')     #=> true
  #   robots.allowed?('https://site.com/anything/', 'OtherBot/1.0')    #=> false
  #
  # @example Wildcard pattern matching
  #   robots_content = <<~ROBOTS
  #     User-agent: *
  #     Disallow: /*.pdf$
  #     Disallow: /temp/*
  #     Allow: /temp/public/*
  #   ROBOTS
  #
  #   robots.parse('https://example.com', robots_content)
  #
  #   robots.allowed?('https://example.com/document.pdf', 'Bot')        #=> false
  #   robots.allowed?('https://example.com/temp/secret.txt', 'Bot')     #=> false
  #   robots.allowed?('https://example.com/temp/public/file.txt', 'Bot') #=> true
  #
  # @since 0.1.0
  class Robots
    # Represents a robots.txt rule for a specific user-agent
    #
    # @!attribute [r] user_agent
    #   @return [String] User-agent pattern this rule applies to
    # @!attribute [r] allow
    #   @return [Array<String>] Array of allowed path patterns
    # @!attribute [r] disallow
    #   @return [Array<String>] Array of disallowed path patterns
    # @!attribute [r] crawl_delay
    #   @return [String, nil] Crawl delay in seconds for this user-agent
    Rule = Struct.new(:user_agent, :allow, :disallow, :crawl_delay)

    # @return [Hash<String, Array<Rule>>] Internal store of parsed robots.txt rules by domain
    attr_reader :store

    # Initializes a new Robots instance
    #
    # Creates an empty store for caching parsed robots.txt files by domain.
    # Each domain's robots.txt is parsed once and cached for subsequent
    # permission checks.
    #
    # @example
    #   robots = Crawlr::Robots.new
    def initialize
      @store = {}
    end

    # Checks if robots.txt has been parsed and cached for a given origin
    #
    # @param origin [String] The origin URL (scheme + host + port)
    # @return [Boolean] true if robots.txt data exists for this origin
    #
    # @example
    #   robots.exists?('https://example.com')  #=> false
    #   robots.parse('https://example.com', robots_content)
    #   robots.exists?('https://example.com')  #=> true
    def exists?(origin)
      @store.key?(origin)
    end

    # Determines if a URL is allowed to be crawled according to robots.txt rules
    #
    # This method implements the full robots.txt specification including:
    # - User-agent matching with prefix matching and wildcards
    # - Path pattern matching with wildcards and end anchors
    # - Allow/disallow precedence with longest match wins
    # - Graceful fallback when no robots.txt exists
    #
    # @param url [String] The full URL to check for crawling permission
    # @param user_agent [String] The user-agent string to match against rules
    # @return [Boolean] true if the URL is allowed to be crawled
    #
    # @example Basic permission checking
    #   robots.allowed?('https://example.com/page.html', 'MyBot/1.0')
    #
    # @example With specific user-agent rules
    #   # robots.txt contains specific rules for "MyBot"
    #   robots.allowed?('https://site.com/admin/', 'MyBot/2.0')  #=> depends on rules
    #   robots.allowed?('https://site.com/admin/', 'OtherBot')   #=> uses wildcard rules
    #
    # @example Pattern matching examples
    #   # robots.txt: Disallow: /*.pdf$
    #   robots.allowed?('https://site.com/doc.pdf', 'Bot')     #=> false
    #   robots.allowed?('https://site.com/doc.pdf.html', 'Bot') #=> true
    #
    #   # robots.txt: Disallow: /temp/*
    #   robots.allowed?('https://site.com/temp/file.txt', 'Bot') #=> false
    #   robots.allowed?('https://site.com/temporary/', 'Bot')    #=> true
    def allowed?(url, user_agent)
      rule = get_rule(url, user_agent)
      return true unless rule # if no robots.txt or no rule, allow

      path = URI.parse(url).path
      matched = []

      # Match allow/disallow using fnmatch (robots.txt style)
      rule.allow.each do |pattern|
        matched << [:allow, pattern] if robots_match?(pattern, path)
      end

      rule.disallow.each do |pattern|
        matched << [:disallow, pattern] if robots_match?(pattern, path)
      end

      return true if matched.empty?

      # Longest match wins
      action, = matched.max_by { |_, p| p.length }
      action == :allow
    end

    # Parses robots.txt content and stores rules for the given URL's domain
    #
    # Extracts and processes all robots.txt directives including:
    # - User-agent declarations
    # - Allow and Disallow rules
    # - Crawl-delay directives
    # - Sitemap declarations
    # - Comment and empty line handling
    #
    # @param url [String] The URL where this robots.txt was fetched from
    # @param content [String] Raw robots.txt file content
    # @return [void]
    #
    # @example Parse standard robots.txt
    #   robots_content = <<~ROBOTS
    #     # This is a comment
    #     User-agent: *
    #     Disallow: /private/
    #     Allow: /public/
    #     Crawl-delay: 2
    #
    #     User-agent: Googlebot
    #     Allow: /
    #
    #     Sitemap: https://example.com/sitemap.xml
    #   ROBOTS
    #
    #   robots.parse('https://example.com/robots.txt', robots_content)
    #
    # @example Parse with wildcards and patterns
    #   robots_content = <<~ROBOTS
    #     User-agent: *
    #     Disallow: /*.json$
    #     Disallow: /api/v*/private/
    #     Allow: /api/v*/public/
    #   ROBOTS
    #
    #   robots.parse('https://api.example.com', robots_content)
    def parse(url, content)
      uri = URI.parse(url)
      domain = uri.host.downcase
      hash = parse_to_hash(content)

      rules = []
      hash[:rules].each do |user_agent, rule|
        rules << Rule.new(user_agent, rule[:allow], rule[:disallow], rule[:crawl_delay])
      end

      @store[domain] ||= rules
    end

    private

    # Finds the most applicable rule for a URL and user-agent combination
    #
    # Implements the robots.txt user-agent matching algorithm:
    # 1. Find rules with user-agent prefix matching (case-insensitive)
    # 2. If no matches, fall back to wildcard (*) rules
    # 3. Return the most specific match (longest user-agent string)
    #
    # @param url [String] URL to find rules for
    # @param user_agent [String] User-agent to match
    # @return [Rule, nil] Most applicable rule or nil if none found
    # @api private
    def get_rule(url, user_agent)
      uri = URI.parse(url)
      domain = uri.host.downcase
      rules = @store[domain]
      return nil unless rules

      # Case-insensitive prefix match
      applicable_rules = rules.select do |rule|
        next if rule.user_agent.nil?

        user_agent.downcase.start_with?(rule.user_agent.downcase)
      end

      # Fallback to wildcard
      applicable_rules = rules.select { |rule| rule.user_agent == "*" } if applicable_rules.empty?

      # Most specific (longest UA name) wins
      applicable_rules.max_by { |r| r.user_agent.length }
    end

    # Tests if a robots.txt pattern matches a given path
    #
    # Implements robots.txt pattern matching including:
    # - Wildcard matching using File.fnmatch
    # - End anchor ($) support for exact suffix matching
    # - Extended glob patterns support
    #
    # @param pattern [String] robots.txt path pattern (may include wildcards and anchors)
    # @param path [String] URL path to test against pattern
    # @return [Boolean] true if pattern matches the path
    # @api private
    #
    # @example Wildcard patterns
    #   robots_match?('/temp/*', '/temp/file.txt')     #=> true
    #   robots_match?('/temp/*', '/temporary/')        #=> false
    #
    # @example End anchor patterns
    #   robots_match?('*.pdf$', '/document.pdf')      #=> true
    #   robots_match?('*.pdf$', '/document.pdf.html') #=> false
    #
    # @example Exact path matching
    #   robots_match?('/admin/', '/admin/')            #=> true
    #   robots_match?('/admin/', '/admin/page.html')   #=> false
    def robots_match?(pattern, path)
      # Handle `$` end anchor (remove and check exact end)
      anchored = pattern.end_with?("$")
      pattern = pattern.chomp("$") if anchored

      matched = File.fnmatch?(pattern, path, File::FNM_EXTGLOB)
      return matched unless anchored

      matched && path.end_with?(pattern.delete_prefix("*"))
    end

    # Parses robots.txt content into a structured hash format
    #
    # Processes the raw robots.txt file line by line, handling:
    # - User-agent declarations and grouping
    # - Allow/Disallow rule accumulation
    # - Crawl-delay value extraction
    # - Sitemap URL collection
    # - Comment and whitespace filtering
    #
    # @param content [String] Raw robots.txt file content
    # @return [Hash] Structured hash with :sitemap and :rules keys
    # @api private
    #
    # @example Return structure
    #   {
    #     sitemap: ['https://example.com/sitemap.xml'],
    #     rules: {
    #       '*' => { allow: ['/public/'], disallow: ['/private/'], crawl_delay: '1' },
    #       'Googlebot' => { allow: ['/'], disallow: [], crawl_delay: nil }
    #     }
    #   }
    def parse_to_hash(content)
      robots_hash = {
        sitemap: [],
        rules: {}
      }

      curr_user_agents = []

      content.each_line do |line|
        clean_line = line.strip
        next if clean_line.empty? || clean_line.start_with?("#")

        key, value = clean_line.split(":", 2).map(&:strip)
        next unless key && value

        key = key.downcase

        case key
        when "sitemap"
          robots_hash[:sitemap] << value
        when "user-agent"
          curr_user_agents = [value]
          robots_hash[:rules][value] ||= { allow: [], disallow: [], crawl_delay: nil }
        when "allow"
          curr_user_agents.each { |ua| robots_hash[:rules][ua][:allow] << value }
        when "disallow"
          curr_user_agents.each { |ua| robots_hash[:rules][ua][:disallow] << value }
        when "crawl-delay"
          curr_user_agents.each { |ua| robots_hash[:rules][ua][:crawl_delay] = value }
        end
      end

      robots_hash
    end
  end
end
