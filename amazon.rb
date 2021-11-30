require 'vacuum'
require 'yaml'
require 'httparty'
require 'active_support/all'

class Amazon
  def initialize
    @client = Vacuum.new(marketplace: ENV['AMAZON_MARKETPLACE'], access_key: ENV['AMAZON_ACCESS_KEY'], secret_key: ENV['AMAZON_ACCESS_SECRET'], partner_tag: ENV['AMAZON_PARTNER_TAG'])
  end

  def check_inventory
    urls = YAML.load_file('products.yml').dig('products', 'amazon')&.map { |u| URI.parse(u) }
    return if urls.blank?

    # Get ASINs out of URLs, split into arrays of 10;
    # API only allows fetching ten products at a time.
    item_ids = urls.map { |u| u.path.match(/\/(dp|gp)(\/product)?\/([\w]+)/)[3] }.compact.uniq.each_slice(10).to_a
    item_ids.each do |ids|
      get_items(item_ids: ids)
      sleep 1
    end
  end

  def get_items(item_ids:)
    resources = [
      'ItemInfo.Title',
      'Offers.Listings.Availability.Type',
      'Offers.Listings.Price',
      'Offers.Listings.MerchantInfo'
    ]
    puts "Fetching data for items #{item_ids.join(', ')}"
    response = @client.get_items(item_ids: item_ids, resources: resources, condition: 'New')
    if response.status == 200
      items = response.to_h.dig('ItemsResult', 'Items')
      items&.map { |i| to_message(i) }&.compact&.each { |i| notify_slack(text: i) }
    else
      puts "[ERROR] #{response.status} – #{response.to_h.dig('Errors')&.map { |e| e.dig('Message') }&.join(', ')}"
    end
  end

  def to_message(item)
    # Find listings that are sold directly by Amazon, not third-party sellers.
    # TODO: Figure out a better way to include legit sellers besides Amazon.
    amazon_listing = item.dig('Offers', 'Listings')&.find { |l| l.dig('MerchantInfo', 'Name') == "Amazon.com" }
    title = item&.dig('ItemInfo', 'Title', 'DisplayValue')
    url = item&.dig('DetailPageURL')
    price = amazon_listing&.dig('Price', 'DisplayAmount')

    if amazon_listing.nil?
      puts "[OUT OF STOCK] #{title} – #{url}"
      return nil
    end

    puts "[IN STOCK] #{title} (#{price}) - #{url}"
    "In stock! #{title} (#{price}): #{url}"
  end

  def notify_slack(text:)
    payload = { text: text, unfurl_links: true }.to_json
    HTTParty.post(ENV['SLACK_WEBHOOK'], body: payload, headers: { 'Content-Type': 'application/json' })
  end
end
