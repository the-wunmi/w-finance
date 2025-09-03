class BankConnectorRegistry
  class << self
    def get_connector(bank_provider)
      connector_class = determine_connector_class(bank_provider)
      connector_class.new(bank_provider)
    end

    private

      def determine_connector_class(bank_provider)
        specific_class_name = "BankConnectors::#{bank_provider.bank_id.classify}Connector"
        return specific_class_name.constantize if specific_class_name.safe_constantize

        BankConnectors::GenericScrapingConnector
      end
  end
end
