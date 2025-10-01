# frozen_string_literal: true

require "http/cookie_jar"

module Crawlr
  # A thread-safe wrapper around the HTTP::CookieJar class
  class CookieJar
    def initialize
      @jar = HTTP::CookieJar.new
      @lock = Concurrent::ReadWriteLock.new
    end

    def add(cookie)
      @lock.with_write_lock { @jar.add(cookie) }
    end

    def cookies(uri)
      @lock.with_read_lock { @jar.cookies(uri) }
    end
  end
end
