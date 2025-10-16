require 'faraday'
require 'json'

class FirestoreClient
  def initialize(credentials:)
    @credentials = credentials
    @base_url = "https://firestore.googleapis.com/v1/projects/#{credentials['projectId']}/databases/(default)/documents"
  end

  def collection(path)
    FirestoreCollection.new(self, path)
  end

  def make_request(method, path, body = nil)
    url = "#{@base_url}/#{path}?key=#{@credentials['apiKey']}"
    
    conn = Faraday.new do |f|
      f.request :json
      f.response :json
      f.adapter Faraday.default_adapter
    end

    response = conn.send(method, url, body)
    
    unless response.success?
      raise "Firestore API error: #{response.status} - #{response.body}"
    end

    response.body
  end

  class FirestoreCollection
    def initialize(client, path)
      @client = client
      @path = path
      @order_by = nil
      @limit_value = nil
    end

    def order(field, direction = :asc)
      @order_by = { field: field, direction: direction }
      self
    end

    def limit(count)
      @limit_value = count
      self
    end

    def get
      query_body = {
        structuredQuery: {
          from: [{ collectionId: @path.split('/').last }]
        }
      }

      if @order_by
        query_body[:structuredQuery][:orderBy] = [{
          field: { fieldPath: @order_by[:field] },
          direction: @order_by[:direction] == :desc ? "DESCENDING" : "ASCENDING"
        }]
      end

      if @limit_value
        query_body[:structuredQuery][:limit] = @limit_value
      end

      # Get parent path for runQuery endpoint
      path_parts = @path.split('/')
      parent_path = path_parts[0..-2].join('/')
      
      response = @client.make_request(:post, "#{parent_path}:runQuery", query_body)
      
      documents = []
      response.each do |doc_data|
        next unless doc_data['document']
        
        doc = FirestoreDocument.new(doc_data['document'])
        documents << doc
      end

      documents
    end
  end

  class FirestoreDocument
    def initialize(document_data)
      @document_data = document_data
    end

    def data
      fields = @document_data['fields'] || {}
      transformed_data = {}
      
      fields.each do |key, value|
        transformed_data[key] = extract_value(value)
      end
      
      transformed_data
    end

    private

    def extract_value(field_value)
      case field_value.keys.first
      when 'stringValue'
        field_value['stringValue']
      when 'integerValue'
        field_value['integerValue'].to_i
      when 'doubleValue'
        field_value['doubleValue'].to_f
      when 'booleanValue'
        field_value['booleanValue']
      when 'timestampValue'
        Time.parse(field_value['timestampValue'])
      when 'nullValue'
        nil
      when 'arrayValue'
        field_value['arrayValue']['values']&.map { |v| extract_value(v) } || []
      when 'mapValue'
        fields = field_value['mapValue']['fields'] || {}
        fields.transform_values { |v| extract_value(v) }
      else
        field_value
      end
    end
  end
end