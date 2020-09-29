require 'vacuum'
require 'yaml'
require 'httparty'

class Amazon
  def initialize
    @client = Vacuum.new(marketplace: ENV['AMAZON_MARKETPLACE'], access_key: ENV['AMAZON_ACCESS_KEY'], secret_key: ENV['AMAZON_ACCESS_SECRET'], partner_tag: ENV['AMAZON_PARTNER_TAG'])
  end

  def check_inventory
    products = YAML.load_file('products.yml')['products']
    # Split ASINs into arrays of 10;
    # API only allows ten at a time.
    item_ids = products.map { |p| p['asin'] }.each_slice(10).to_a
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
    puts "Requesting product information for IDs: #{item_ids.join(', ')}"
    response = @client.get_items(item_ids: item_ids, resources: resources, condition: 'New')
    if response.status == 200
      items = response.to_h.dig('ItemsResult', 'Items')
      items.each do |item|
        title = item.dig('ItemInfo', 'Title', 'DisplayValue')
        url = item.dig('DetailPageURL')

        # Find listings that:
        # 1. Are available now (not for preorder or backordered)
        # 2. Are sold directly by Amazon, not third-party sellers
        # 3. Are available on Prime
        amazon_listing = item.dig('Offers', 'Listings')&.find { |l| l.dig('Availability', 'Type') == 'Now' && l.dig('DeliveryInfo', 'IsAmazonFulfilled') && l.dig('DeliveryInfo', 'IsPrimeEligible') }
        
        if amazon_listing.nil?
          puts "[OUT OF STOCK] #{title} – #{url}"
        else
          puts "[IN STOCK] #{title} – #{url}"
          image = item.dig('Images', 'Primary', 'Large', 'URL')
          price = amazon_listing.dig('Price', 'DisplayAmount')
          notify_slack(title: title, url: url, image: image, price: price)
        end
      end
    else
      puts "[ERROR] #{response.status} – #{response.body}"
    end
  end

  def notify_slack(title:, url:, image:, price:)
    attachment = {
      fallback: "In stock! #{title} (#{price}): #{url}",
      pretext: 'In stock!',
      title: title,
      title_link: url,
      fields: [{ title: 'Price', short: true, value: price }],
      thumb_url: image
    }
    payload = { text: '', attachments: [attachment] }.to_json
    HTTParty.post(ENV['SLACK_WEBHOOK'], body: payload, headers: { 'Content-Type': 'application/json' })
  end
end