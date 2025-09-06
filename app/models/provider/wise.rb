class Provider::Wise < Provider
  include ExchangeRateConcept

  Error = Class.new(Provider::Error)
  InvalidExchangeRateError = Class.new(Error)

  def initialize(api_key)
    @api_key = api_key
  end

  def fetch_exchange_rate(from:, to:, date:)
    with_provider_response do
      time_param = date.beginning_of_day.iso8601

      response = client.get("#{base_url}/v1/rates") do |req|
        req.params["source"] = from
        req.params["target"] = to
        req.params["time"] = time_param
      end

      rates = Array(response.body)
      rate_entry = rates.first

      if rate_entry.nil? || rate_entry["rate"].nil?
        Rails.logger.warn("#{self.class.name} returned no rate data for pair from: #{from} to: #{to} on: #{date}")
        Sentry.capture_exception(InvalidExchangeRateError.new("#{self.class.name} returned no rate data"), level: :warning) do |scope|
          scope.set_context("rate", { from: from, to: to, date: date })
        end
        return nil
      end

      Rate.new(date: date.to_date, from: from, to: to, rate: rate_entry["rate"])
    end
  end

  def fetch_exchange_rates(from:, to:, start_date:, end_date:)
    with_provider_response do
      from_param = start_date.beginning_of_day.iso8601
      to_param = end_date.end_of_day.iso8601

      response = client.get("#{base_url}/v1/rates") do |req|
        req.params["source"] = from
        req.params["target"] = to
        req.params["from"] = from_param
        req.params["to"] = to_param
        req.params["group"] = "day"
      end

      rates = Array(response.body)

      rates.map do |rate_entry|
        date_str = rate_entry["time"]
        rate_value = rate_entry["rate"]

        if date_str.nil? || rate_value.nil?
          Rails.logger.warn("#{self.class.name} returned invalid rate data for pair from: #{from} to: #{to} on: #{date_str}.  Rate data: #{rate_entry.inspect}")
          Sentry.capture_exception(InvalidExchangeRateError.new("#{self.class.name} returned invalid rate data"), level: :warning) do |scope|
            scope.set_context("rate", { from: from, to: to, date: date_str })
          end

          next
        end

        Rate.new(date: Date.parse(date_str), from: from, to: to, rate: rate_value)
      end.compact
    end
  end

  private
    attr_reader :api_key

    def client
      @client ||= Faraday.new(url: base_url) do |conn|
        conn.request :retry, {
          max: 2,
          interval: 0.05,
          interval_randomness: 0.5,
          backoff_factor: 2
        }

        conn.response :raise_error
        conn.response :json

        conn.headers["Authorization"] = "Bearer #{api_key}"
        conn.adapter Faraday.default_adapter
      end
    end

    def base_url
      ENV["WISE_BASE_URL"]
    end
end
