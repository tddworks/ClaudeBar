import DataSources

/// DataSources' port, named apart from the AWS SDK's own `CloudWatchClient`
/// (this file imports only DataSources, so the name is unambiguous here).
typealias CloudWatchPort = CloudWatchClient
