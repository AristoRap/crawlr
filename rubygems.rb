require "lib/crawlr"

clct = Crawlr::Collector.new
gems = []

clct.visit("https://rubygems.org/releases/popular") do |collector|
  collector.on_html(:css, ".main--interior a.gems__gem") do |node, ctx|
    link = node["href"]
    full_link = ctx.resolve_url(link) if link
    gems << full_link
  end
end

puts "Found #{gems.size} gems"

gems.each do |gem|
  puts gem
end
