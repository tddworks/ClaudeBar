import DataSources

/// The AWS SDK, linked here and nowhere else (MODULAR_DESIGN §2): the
/// CloudWatch metrics a `cloudWatch` fetch sums, and the Bedrock price list
/// that prices them.
public enum AWSClients {
    public static func makeCloudWatch() -> any CloudWatchClient {
        SDKCloudWatchClient()
    }

    public static func makePriceCatalog() -> any PriceCatalog {
        SDKPriceCatalog(pricing: AWSBedrockPricingService())
    }
}
