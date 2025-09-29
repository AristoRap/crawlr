require_relative "../lib/crawlr"

# Create a new collector instance
clct = Crawlr::Collector.new
gems = []

# Visit the RubyGems popular releases page
clct.visit("https://rubygems.org/releases/popular") do |collector|
  # Extract gem links using a CSS selector
  # The callback will be executed for each matched node
  collector.on_html(:css, ".main--interior a.gems__gem") do |node, ctx|
    link = node["href"]
    gems << ctx.resolve_url(link) if link
  end
end

# Print results
puts "Found #{gems.size} gems"
gems.each { |g| puts g }
