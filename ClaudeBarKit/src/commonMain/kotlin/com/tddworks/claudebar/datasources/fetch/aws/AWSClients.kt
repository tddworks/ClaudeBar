package com.tddworks.claudebar.datasources.fetch.aws

import com.tddworks.claudebar.datasources.CloudWatchClient
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.PriceCatalog
import kotlin.time.Clock

/**
 * AWS without its SDK: the CloudWatch metrics a `cloudWatch` fetch sums and the price list
 * that prices them, signed with SigV4 over [NetworkClient], with the person's credentials
 * from [home]'s `~/.aws` and [environment]. [now] is seconds since 1970.
 */
internal object AWSClients {
    fun cloudWatch(
        network: NetworkClient,
        home: String,
        environment: (String) -> String?,
        now: () -> Double = ::nowSeconds,
    ): CloudWatchClient = AWSCloudWatchClient(AWSCaller(network, AWSCredentialResolver(home, environment), now))

    fun priceCatalog(
        network: NetworkClient,
        home: String,
        environment: (String) -> String?,
        now: () -> Double = ::nowSeconds,
    ): PriceCatalog = AWSPriceCatalog(PriceListModelPricing(AWSCaller(network, AWSCredentialResolver(home, environment), now), now))

    private fun nowSeconds() = Clock.System.now().toEpochMilliseconds() / 1000.0
}
