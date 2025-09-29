# frozen_string_literal: true

require "spec_helper"
require "crawlr/http_interface"
require "crawlr/config"

RSpec.describe Crawlr::HTTPInterface do
  let(:config) { Crawlr::Config.new }
  let(:http_interface) { described_class.new(config) }

  describe "#initialize" do
    it "initializes with default options" do
      expect(http_interface.config.timeout).to eq(10)
      expect(http_interface.config.headers).to include("User-Agent")
    end

    it "sets custom options" do
      custom_config = Crawlr::Config.new(
        timeout: 30,
        default_headers: { "Custom-Header" => "value" },
        allow_cookies: true
      )
      custom_http = described_class.new(custom_config)

      expect(custom_http.config.timeout).to eq(30)
      expect(custom_http.config.headers).to include("Custom-Header" => "value")
      expect(custom_http.config.allow_cookies).to be true
    end
  end

  describe "#get" do
    let(:mock_internet) { double("internet", get: mock_response, close: nil) }

    let(:mock_response) do
      double("response",
             status: 200,
             headers: {},
             version: "1.1",
             read: "<html>test</html>",
             close: nil)
    end

    before do
      allow(http_interface).to receive(:build_internet_connection).and_return(mock_internet)
      allow(mock_internet).to receive(:get).and_return(mock_response)
      allow(Crawlr.logger).to receive(:debug)
    end

    it "fetches URL successfully" do
      expect(mock_internet).to receive(:get)
        .with("https://example.com", http_interface.config.headers)

      response = http_interface.get("https://example.com")

      expect(response).to be_a(Crawlr::HTTPInterface::Response)
      expect(response.url).to eq("https://example.com")
      expect(response.status).to eq(200)
      expect(response.body).to eq("<html>test</html>")
    end

    it "handles timeout errors" do
      allow(mock_internet).to receive(:get).and_raise(Async::TimeoutError)
      expect(Crawlr.logger).to receive(:warn).with(/Timeout fetching/)

      expect { http_interface.get("https://example.com") }.to raise_error(Async::TimeoutError)
    end

    it "handles response read errors" do
      allow(mock_response).to receive(:read).and_raise(StandardError.new("Read error"))

      response = http_interface.get("https://example.com")
      expect(response.body).to be_nil
    end
  end

  describe "cookie handling" do
    let(:http_with_cookies) do
      cfg = Crawlr::Config.new(allow_cookies: true)
      described_class.new(cfg)
    end

    let(:mock_internet) { double("internet", get: nil, close: nil) }

    let(:first_response) do
      double("response",
             status: 200,
             headers: { "set-cookie" => ["session=abc123; Path=/"] },
             version: "1.1",
             read: "<html>first</html>",
             close: nil)
    end
    let(:second_response) do
      double("response",
             status: 200,
             headers: {},
             version: "1.1",
             read: "<html>second</html>",
             close: nil)
    end

    before do
      allow(http_with_cookies).to receive(:build_internet_connection).and_return(mock_internet)

      allow(Crawlr.logger).to receive(:debug)
    end

    it "stores cookies from first response and sends them on second request" do
      # First request returns Set-Cookie
      expect(mock_internet).to receive(:get)
        .with("https://example.com", anything)
        .and_return(first_response)

      http_with_cookies.get("https://example.com")

      # Second request should include the stored cookie in headers
      expect(mock_internet).to receive(:get) do |url, headers|
        expect(url).to eq("https://example.com/next")
        expect(headers["cookie"]).to match(/session=abc123/) # verify cookie is sent
        second_response
      end

      http_with_cookies.get("https://example.com/next")
    end

    it "does not send cookies to a different domain" do
      # First request sets a cookie for example.com
      allow(mock_internet).to receive(:get).and_return(first_response)
      http_with_cookies.get("https://example.com")

      # Request to another domain should NOT send the cookie
      expect(mock_internet).to receive(:get) do |url, headers|
        expect(url).to eq("https://other.com/page")
        expect(headers["cookie"]).to be_nil
        second_response
      end

      http_with_cookies.get("https://other.com/page")
    end
  end

  describe "Response struct" do
    it "creates response with all attributes" do
      response = Crawlr::HTTPInterface::Response.new(
        "https://example.com",
        200,
        { "content-type" => "text/html" },
        "1.1",
        "<html></html>"
      )

      expect(response.url).to eq("https://example.com")
      expect(response.status).to eq(200)
      expect(response.headers).to eq({ "content-type" => "text/html" })
      expect(response.version).to eq("1.1")
      expect(response.body).to eq("<html></html>")
    end
  end
  describe "proxy handling" do
    let(:proxies) { ["http://proxy1:8080", "http://proxy2:8080"] }
    let(:config) do
      Crawlr::Config.new(
        proxies: proxies,
        strategy: :round_robin,
        headers: { "User-Agent" => "CrawlrBot" }
      )
    end
    let(:http_interface) { described_class.new(config) }
    let(:mock_internet) { double("internet", get: mock_response, close: nil) }
    let(:mock_response) do
      double("response", status: 200, headers: {}, version: "1.1", read: "ok", close: nil)
    end

    before do
      allow(http_interface).to receive(:build_internet_connection).and_return(mock_internet)
      allow(Crawlr.logger).to receive(:debug)
    end

    it "rotates proxies in round robin order" do
      expect(http_interface).to receive(:build_internet_connection).with("http://proxy1:8080").ordered
      http_interface.get("https://example.com")

      expect(http_interface).to receive(:build_internet_connection).with("http://proxy2:8080").ordered
      http_interface.get("https://example.com")

      expect(http_interface).to receive(:build_internet_connection).with("http://proxy1:8080").ordered
      http_interface.get("https://example.com")
    end

    it "uses random proxy strategy" do
      config.proxy_strategy = :random
      expect(proxies).to include(http_interface.send(:next_proxy))
    end
  end
end
