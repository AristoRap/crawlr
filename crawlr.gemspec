# frozen_string_literal: true

require_relative "lib/crawlr/version"

Gem::Specification.new do |spec|
  spec.name = "crawlr"
  spec.version = Crawlr::VERSION
  spec.authors = ["Aristotelis Rapai"]
  spec.email = ["aristorap.dev@gmail.com"]

  spec.summary = "A powerful, async Ruby web scraping framework"
  spec.description = <<~DESC
    Crawlr is a modern Ruby web scraping framework built for respectful and efficient data extraction.
    Features async HTTP requests, robots.txt compliance, cookie management, proxy rotation, flexible
    CSS/XPath selectors, and comprehensive error handling. Designed for both simple scraping tasks
    and complex, large-scale data extraction projects.
  DESC

  spec.homepage = "https://github.com/aristorap/crawlr"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  # Metadata for RubyGems
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/aristorap/crawlr"
  spec.metadata["changelog_uri"] = "https://github.com/aristorap/crawlr/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/aristorap/crawlr/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?("bin/", "test/", "spec/", "features/", ".git", ".github", "appveyor", "Gemfile")
    end
  end

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Dependencies
  spec.add_runtime_dependency "async", "~> 2.32"
  spec.add_runtime_dependency "async-http", "~> 0.91.0"
  spec.add_runtime_dependency "concurrent-ruby", "~> 1.3"
  spec.add_runtime_dependency "http-cookie", "~> 1.0"
  spec.add_runtime_dependency "nokogiri", "~> 1.18"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.60"
  spec.add_development_dependency "ruby-prof", "~> 1.7"
  spec.add_development_dependency "webmock", "~> 3.25"
end
