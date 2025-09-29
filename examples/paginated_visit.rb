require_relative "../lib/crawlr"

# Create a new collector instance
clct = Crawlr::Collector.new(
  max_depth: 2,
  random_delay: 1,
  max_parallelism: 5
)
mu = Mutex.new
gems = []

# Visit the RubyGems popular releases page with pagination
# Set max depth in collector config to limit crawl depth
clct.paginated_visit("https://rubygems.org/releases/popular") do |collector|
  # Extract gem links using a CSS selector
  collector.on_html(:css, ".main--interior a.gems__gem") do |node, ctx|
    link = node["href"]
    if link
      full_link = ctx.resolve_url(link) # Resolve relative URL using context helper method
      mu.synchronize { gems << full_link }
    end
  end
end

# Print results
puts "Found #{gems.size} gems"
gems.each { |g| puts g }
