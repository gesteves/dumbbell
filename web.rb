require 'yaml'
require 'httparty'
require 'nokogiri'
require 'active_support/all'

class Web
  def initialize
  end

  def check_inventory
    products = YAML.load_file('products.yml')['products']['web']
    products.each do |product|
      name = product['name']
      url = product['url']
      selector = product['selector']
      if in_stock?(url: url, selector: selector)
        puts "[IN STOCK] #{name} – #{url}"
        notify_slack(text: "In stock! #{name}: #{url}")
      else
        puts "[OUT OF STOCK] #{name} – #{url}"
      end
    end
  end

  def in_stock?(url:, selector:)
    response = HTTParty.get(url)
    return false if response.code >= 400

    body = response.body
    doc = Nokogiri::HTML(body)
    doc.css(selector).present?
  end

  def notify_slack(text:)
    payload = { text: text }.to_json
    HTTParty.post(ENV['SLACK_WEBHOOK'], body: payload, headers: { 'Content-Type': 'application/json' })
  end
end
