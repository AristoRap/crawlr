require_relative "../lib/crawlr"

# Create a new collector instance
clct = Crawlr::Collector.new(
  max_depth: 2, # Limit unbounded crawls
  random_delay: 1, # Maximum random delay between requests
  max_parallelism: 5 # Maximum concurrent requests
)

# Create a map to store gem metadata
# Use a thread-safe map due to parallel processing
gems_meta = Concurrent::Map.new

# Visit the RubyGems popular releases page
clct.visit("https://rubygems.org/releases/popular") do |c|
  # Grab main container
  c.on_html(:css, ".main--interior") do |node, ctx|
    # Grab all gem links
    gems = []
    node.css("a.gems__gem").each do |a|
      gems << ctx.resolve_url(a["href"])
    end
    # Visit each gem page
    c.visit(gems, ctx.increment_depth) # Use context helper method to set depth for accurate tracking
  end

  # This callback will be matched on the individual gem pages
  c.on_html(:css, "h2.gem__downloads__heading:nth-child(1) > span:nth-child(1)") do |node, ctx|
    gems_meta[ctx.page_url] = node.text
  end
end

# Print results
puts "Found #{gems_meta.size} gems"

gems_meta.each_pair { |k, v| puts "#{k} => #{v}" }
