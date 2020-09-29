require 'vacuum'
require 'yaml'
require 'httparty'

class Amazon
  def initialize
    @client = Vacuum.new(marketplace: ENV['AMAZON_MARKETPLACE'], access_key: ENV['AMAZON_ACCESS_KEY'], secret_key: ENV['AMAZON_ACCESS_SECRET'], partner_tag: ENV['AMAZON_PARTNER_TAG'])
  end

  def check_inventory
    urls = YAML.load_file('products.yml')['products'].map { |u| URI.parse(u) }
    # Get ASINs out of URLs, split into arrays of 10;
    # API only allows fetching ten products at a time.
    item_ids = urls.select { |u| u.host == 'www.amazon.com' }.map { |u| u.path.match(/\/dp\/([\w]+)/)[1] }.compact.each_slice(10).to_a
    item_ids.each do |ids|
      get_items(item_ids: ids)
      sleep 1
    end
  end

  def get_items(item_ids:)
    resources = [
      'Images.Primary.Large',
      'ItemInfo.Title',
      'Offers.Listings.Availability.Type',
      'Offers.Listings.DeliveryInfo.IsAmazonFulfilled',
      'Offers.Listings.DeliveryInfo.IsPrimeEligible',
      'Offers.Listings.Price'
    ]
    puts "Fetching data for items #{item_ids.join(', ')}"
    response = @client.get_items(item_ids: item_ids, resources: resources, condition: 'New')
    if response.status == 200
      items = response.to_h.dig('ItemsResult', 'Items')
      attachments = items&.map { |item| to_attachment(item) }&.compact
      notify_slack(text: 'In stock!', attachments: attachments) unless attachments.empty?
    else
      puts "[ERROR] #{response.status} – #{response.body}"
    end
  end

  def to_attachment(item)
    # Find listings that:
    # 1. Are available now (not for preorder or backordered)
    # 2. Are sold directly by Amazon, not third-party sellers
    # 3. Are available on Prime
    amazon_listing = item.dig('Offers', 'Listings')&.find { |l| l.dig('Availability', 'Type') == 'Now' && l.dig('DeliveryInfo', 'IsAmazonFulfilled') && l.dig('DeliveryInfo', 'IsPrimeEligible') }
    title = item.dig('ItemInfo', 'Title', 'DisplayValue')
    url = item.dig('DetailPageURL')

    if amazon_listing.nil?
      puts "[OUT OF STOCK] #{title} – #{url}"
      return nil
    end

    puts "[IN STOCK] #{title} – #{url}"
    image = item.dig('Images', 'Primary', 'Large', 'URL')
    price = amazon_listing.dig('Price', 'DisplayAmount')

    {
      fallback: "#{title} (#{price}): #{url}",
      title: title,
      title_link: url,
      fields: [{ title: 'Price', short: true, value: price }],
      thumb_url: image
    }
  end

  def notify_slack(text:, attachments:)
    payload = { text: text, attachments: attachments }.to_json
    HTTParty.post(ENV['SLACK_WEBHOOK'], body: payload, headers: { 'Content-Type': 'application/json' })
  end
end
