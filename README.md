# crawlr 🕷️

A powerful, async Ruby web scraping framework designed for respectful and efficient data extraction. Built with modern Ruby practices, crawlr provides a clean API for scraping websites while respecting robots.txt, managing cookies, rotating proxies, and handling complex scraping scenarios.

[![Gem Version](https://badge.fury.io/rb/crawlr.svg)](https://badge.fury.io/rb/crawlr)
[![Ruby](https://github.com/aristorap/crawlr/actions/workflows/ruby.yml/badge.svg)](https://github.com/aristorap/crawlr/actions/workflows/ruby.yml)

## ✨ Features

- 🚀 **Async HTTP requests** with configurable concurrency
- 🤖 **Robots.txt compliance** with automatic parsing and rule enforcement
- 🍪 **Cookie management** with automatic persistence across requests
- 🔄 **Proxy rotation** with round-robin and random strategies
- 🎯 **Flexible selectors** supporting both CSS and XPath
- 🔧 **Extensible hooks** for request/response lifecycle events
- 📊 **Built-in statistics** and monitoring capabilities
- 🛡️ **Respectful crawling** with delays, depth limits, and visit tracking
- 🧵 **Thread-safe** operations for parallel scraping
- 📄 **Comprehensive logging** with configurable levels

## 📦 Installation

Add this line to your application's Gemfile:

```ruby
gem 'crawlr'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install crawlr
```

## 🚀 Quick Start

```ruby
require 'crawlr'

# Create a collector with configuration
collector = Crawlr::Collector.new(
  max_depth: 3,
  max_parallelism: 5,
  random_delay: 1.0,
  timeout: 15
)

# Register callbacks for data extraction
collector.on_html(:css, '.article-title') do |node, context|
  puts "Found title: #{node.text.strip}"
end

collector.on_html(:css, 'a[href]') do |link, context|
  href = link['href']
  puts "Found link: #{href}" if href.start_with?('http')
end

# Start scraping
collector.visit('https://example.com')
```

## 📚 Usage Examples

### Basic Web Scraping

```ruby
collector = Crawlr::Collector.new
products = []
# Extract product information
collector.visit('https://shop.example.com/products') do |c|
  c.on_html(:css, '.product') do |product, ctx|
    data = {
      name: product.css('.product-name').text.strip,
      price: product.css('.price').text.strip,
      image: product.css('img')&.first&.[]('src')
    }
  
    products << data
  end
end
# do something with data
```

### API Scraping with Pagination

```ruby
collector = Crawlr::Collector.new(
  max_parallelism: 10,
  timeout: 30
)
mu = Mutex.new
items = Array.new

collector.on_xml(:css, 'item') do |item, _ctx|
  data =  {
    id: item.css('id').text,
    title: item.css('title').text,
    published: item.css('published').text
  }
  mu.synchronize { items << data }
end

# Automatically handles pagination with ?page=1, ?page=2, etc.
collector.paginated_visit(
  'https://api.example.com/feed',
  batch_size: 5,
  start_page: 1
)
```

### Advanced Configuration

```ruby
collector = Crawlr::Collector.new(
  # Network settings
  timeout: 20,
  max_parallelism: 8,
  random_delay: 2.0,

  # Crawling behavior
  max_depth: 5,
  allow_url_revisit: false,
  max_visited: 50_000,

  # Proxy rotation
  proxies: ['proxy1.com:8080', 'proxy2.com:8080'],
  proxy_strategy: :round_robin,

  # Respectful crawling
  ignore_robots_txt: false,
  allow_cookies: true,

  # Error handling
  max_retries: 3,
  retry_delay: 1.0,
  retry_backoff: 2.0
)
```

### Domain Filtering

```ruby
# Allow specific domains
collector = Crawlr::Collector.new(
  allowed_domains: ['example.com', 'api.example.com']
)

# Or use glob patterns
collector = Crawlr::Collector.new(
  domain_glob: ['*.example.com', '*.trusted-site.*']
)
```

### Hooks for Custom Behavior

```ruby
# Add custom headers before each request
collector.hook(:before_visit) do |url, headers|
  headers['Authorization'] = "Bearer #{get_auth_token()}"
  headers['X-Custom-Header'] = 'MyBot/1.0'
  puts "Visiting: #{url}"
end

# Process responses after each request
collector.hook(:after_visit) do |url, response|
  puts "Got #{response.status} from #{url}"
end

# Handle errors gracefully
collector.hook(:on_error) do |url, error|
  puts "Failed to scrape #{url}: #{error.message}"
end
```

### XPath Selectors

```ruby
collector.on_html(:xpath, '//div[@class="content"]//p[position() <= 3]') do |paragraph, ctx|
  # Do stuff
end

collector.on_xml(:xpath, '//item[price > 100]/title') do |title, ctx|
  # Do stuff
end
```

### Session Management with Cookies

```ruby
collector = Crawlr::Collector.new(allow_cookies: true)

# First visit will set cookies tor following requests
collector.visit('https://site.com/login')
collector.visit('https://site.com/protected-content') # Uses login cookies
```

### Stats

```ruby
collector = Crawlr::Collector.new

# Get comprehensive statistics
stats = collector.stats
puts "Visited #{stats[:total_visits]} pages"
puts "Active callbacks: #{stats[:callbacks_count]}"
puts "Memory usage: #{stats[:visited_count]}/#{stats[:max_visited]} URLs tracked"

# Clone collectors for different tasks while sharing HTTP connections
product_scraper = collector.clone
product_scraper.on_html(:css, '.product') { |node, ctx| extract_product(node, ctx) }

review_scraper = collector.clone
review_scraper.on_html(:css, '.review') { |node, ctx| extract_review(node, ctx) }
```

## 🏗️ Architecture

crawlr is built with a modular architecture:

- **Collector**: Main orchestrator managing the scraping workflow
- **HTTPInterface**: Async HTTP client with proxy and cookie support
- **Parser**: Document parsing engine using Nokogiri
- **Callbacks**: Flexible callback system for data extraction
- **Hooks**: Event system for request/response lifecycle customization
- **Config**: Centralized configuration management
- **Visits**: Thread-safe URL deduplication and visit tracking
- **Domains**: Domain filtering and allowlist management
- **Robots**: Robots.txt parsing and compliance checking

## 🤝 Respectful Scraping

crawlr is designed to be a responsible scraping framework:

- **Robots.txt compliance**: Automatically fetches and respects robots.txt rules
- **Rate limiting**: Built-in delays and concurrency controls
- **User-Agent identification**: Clear identification in requests
- **Error handling**: Graceful handling of failures without overwhelming servers
- **Memory management**: Automatic cleanup to prevent resource exhaustion

## 🔧 Configuration Options

| Option              | Default | Description                              |
| ------------------- | ------- | ---------------------------------------- |
| `timeout`           | 10      | HTTP request timeout in seconds          |
| `max_parallelism`   | 1       | Maximum concurrent requests              |
| `max_depth`         | 0       | Maximum crawling depth (0 = unlimited)   |
| `random_delay`      | 0       | Maximum random delay between requests    |
| `allow_url_revisit` | false   | Allow revisiting previously scraped URLs |
| `max_visited`       | 10,000  | Maximum URLs to track before cache reset |
| `allow_cookies`     | false   | Enable cookie jar management             |
| `ignore_robots_txt` | false   | Skip robots.txt checking                 |
| `max_retries`       | nil     | Maximum retry attempts (nil = disabled)  |
| `retry_delay`       | 1.0     | Base delay between retries               |
| `retry_backoff`     | 2.0     | Exponential backoff multiplier           |

## 🧪 Testing

Run the test suite:

```bash
bundle exec rspec
```

Run with coverage:

```bash
COVERAGE=true bundle exec rspec
```

## 📖 Documentation

Generate API documentation:

```bash
yard doc
```

View documentation:

```bash
yard server
```

## 🤝 Contributing

1. Fork it (https://github.com/aristorap/crawlr/fork)
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes with tests
4. Ensure all tests pass (`bundle exec rspec`)
5. Commit your changes (`git commit -am 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Create a new Pull Request

## 📝 License

This gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## 🙏 Acknowledgments

- Built with [Nokogiri](https://nokogiri.org/) for HTML/XML parsing
- Uses [Async](https://github.com/socketry/async) for high-performance concurrency
- Inspired by Golang's [Colly](https://go-colly.org) framework and modern Ruby practices
## 📞 Support

- 📖 [Documentation TBD](https://aristorap.github.io/crawlr)
- 🐛 [Issue Tracker](https://github.com/aristorap/crawlr/issues)

---

**Happy Scraping! 🕷️✨**
