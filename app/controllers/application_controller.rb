class ApplicationController < ActionController::API

  require 'net/http'
  require 'csv'

  before_action :construct_payload_for_scraping, :scrape

  def main
    # csv_headers =
    # CSV.open("output.csv", "wb", write_headers: true, headers: csv_headers) do |csv|
    #   # adding each product as a new row
    #   # to the output CSV file
    #   @result.each do |iterator|
    #     csv << iterator.values_at(*csv_headers)
    #   end
    # end
    # send_data(pdf.render, filename: 'test.pdf', disposition: 'inline', type: 'application/pdf')

    csv_headers = %w[company_name location short_description yc_batch website founder_names linked_in_urls]

    csv_data = CSV.generate(headers: true) do |csv|
      csv << csv_headers
      @result.each do |iterator|
        csv << iterator.values
      end
    end

    send_data csv_data, filename: "company_data-#{Date.today.to_s}.csv", disposition: :attachment
  end

  private

  def scrape
    @result = []
    url = URI("https://45bwzj1sgc-dsn.algolia.net/1/indexes/*/queries?x-algolia-agent=Algolia%20for%20JavaScript%20(3.35.1)%3B%20Browser%3B%20JS%20Helper%20(3.16.1)&x-algolia-application-id=45BWZJ1SGC&x-algolia-api-key=MjBjYjRiMzY0NzdhZWY0NjExY2NhZjYxMGIxYjc2MTAwNWFkNTkwNTc4NjgxYjU0YzFhYTY2ZGQ5OGY5NDMxZnJlc3RyaWN0SW5kaWNlcz0lNUIlMjJZQ0NvbXBhbnlfcHJvZHVjdGlvbiUyMiUyQyUyMllDQ29tcGFueV9CeV9MYXVuY2hfRGF0ZV9wcm9kdWN0aW9uJTIyJTVEJnRhZ0ZpbHRlcnM9JTVCJTIyeWNkY19wdWJsaWMlMjIlNUQmYW5hbHl0aWNzVGFncz0lNUIlMjJ5Y2RjJTIyJTVE")

    request = Net::HTTP::Post.new(url)
    request['Connection'] = 'keep-alive'
    request['accept'] = 'application/json'
    request['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36'
    request['content-type'] = 'application/x-www-form-urlencoded'
    request['Origin'] = 'https://www.ycombinator.com'
    request['Referer'] = 'https://www.ycombinator.com/'
    request.body = @filters.to_json
    client = Net::HTTP.new(url.host, url.port)
    client.use_ssl = true
    response = client.request(request)
    data = JSON.parse(response.body)
    data = data.dig('results', 0, 'hits')
    if data
      data.each do |iterator|
        company_url = URI.parse("https://www.ycombinator.com/companies/#{iterator['slug']}")
        company_request = Net::HTTP::Get.new(company_url)
        company_request['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36'

        show_page = Net::HTTP.new(company_url.host, company_url.port)
        show_page.use_ssl = true
        company_response = Nokogiri::HTML(show_page.request(company_request).body)
        founder_names = []
        linked_in_urls = []
        if company_response
          company_response.css('div.flex.flex-row.items-center.gap-x-3').each do |element|
            founder_names << element.css("div.leading-snug").children.text.strip
            linked_in_urls << element.css("a.bg-image-linkedin").first["href"] unless element.css("a.bg-image-linkedin").blank?
          end
          @result << {
            company_name: iterator['name'],
            location: iterator['all_locations'],
            short_description: iterator.dig('_highlightResult', 'one_liner', 'value'),
            yc_batch: iterator['batch'],
            website: iterator['website'],
            founder_names: founder_names,
            linked_in_urls: linked_in_urls,
          }
        end
      end
    end

  end

  def construct_payload_for_scraping
    facetFilters = []
    facetFilters << ["batch:#{filter_params[:filters][:batch]}"] if filter_params.dig(:filters, :batch)
    facetFilters << ["industries:#{filter_params[:filters][:industry]}"] if filter_params.dig(:filters, :industry)
    facetFilters << ["highlight_black:true"] if filter_params.dig(:filters, :black_founded)
    facetFilters << ["highlight_latinx:true"] if filter_params.dig(:filters, :hispanic_latino_founded)
    facetFilters << ["highlight_women:true"] if filter_params.dig(:filters, :women_founded)
    facetFilters << ["regions:#{filter_params[:filters][:region]}"] if filter_params.dig(:filters, :region)
    facetFilters << ["isHiring:true"] if filter_params.dig(:filters, :is_hiring)
    facetFilters << ["nonprofit:true"] if filter_params.dig(:filters, :nonprofit)
    team_size = ""
    if filter_params[:filters][:company_size]
      size = filter_params[:filters][:company_size].split("-").last
      team_size = "[\"team_size<=#{size.to_i}\"]"
    end
    @filters = {
      "requests": [
        {
          "indexName": "YCCompany_production",
          "hitsPerPage": filter_params[:n].presence || 30,
        }
      ]
    }
    @filters[:requests][0][:facetFilters] = facetFilters if facetFilters
    @filters[:requests][0][:numericFilters] = team_size if team_size
    tag = filter_params.dig(:filters, :tag)
    @filters[:requests][0][:facetQuery] = tag if tag
  end

  def filter_params
    params.permit(:n, :filters => [:batch, :industry, :region, :tag, :company_size, :is_hiring, :nonprofit, :black_founded, :hispanic_latino_founded, :women_founded])
  end
end
