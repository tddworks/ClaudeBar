import Testing
@testable import Domain

@Suite
struct MiniMaxRegionTests {

    // MARK: - displayName

    @Test
    func `international displayName`() {
        #expect(MiniMaxRegion.international.displayName == "International (minimax.io)")
    }

    @Test
    func `china displayName`() {
        #expect(MiniMaxRegion.china.displayName == "China (minimaxi.com)")
    }

    // MARK: - apiBaseURL

    @Test
    func `international apiBaseURL`() {
        #expect(MiniMaxRegion.international.apiBaseURL == "https://api.minimax.io")
    }

    @Test
    func `china apiBaseURL`() {
        #expect(MiniMaxRegion.china.apiBaseURL == "https://api.minimaxi.com")
    }

    // MARK: - platformURL

    @Test
    func `international platformURL`() {
        #expect(MiniMaxRegion.international.platformURL == "https://platform.minimax.io")
    }

    @Test
    func `china platformURL`() {
        #expect(MiniMaxRegion.china.platformURL == "https://platform.minimaxi.com")
    }

    // MARK: - apiKeysURL

    @Test
    func `international apiKeysURL`() {
        #expect(MiniMaxRegion.international.apiKeysURL.absoluteString ==
            "https://platform.minimax.io/user-center/basic-information/interface-key")
    }

    @Test
    func `china apiKeysURL`() {
        #expect(MiniMaxRegion.china.apiKeysURL.absoluteString ==
            "https://platform.minimaxi.com/user-center/basic-information/interface-key")
    }

    // MARK: - dashboardURL

    @Test
    func `international dashboardURL`() {
        #expect(MiniMaxRegion.international.dashboardURL.absoluteString ==
            "https://platform.minimax.io/user-center/payment/coding-plan")
    }

    @Test
    func `china dashboardURL`() {
        #expect(MiniMaxRegion.china.dashboardURL.absoluteString ==
            "https://platform.minimaxi.com/user-center/payment/coding-plan")
    }

    // MARK: - codingPlanRemainsURL

    @Test
    func `international codingPlanRemainsURL`() {
        #expect(MiniMaxRegion.international.codingPlanRemainsURL ==
            "https://api.minimax.io/v1/token_plan/remains")
    }

    @Test
    func `china codingPlanRemainsURL`() {
        #expect(MiniMaxRegion.china.codingPlanRemainsURL ==
            "https://api.minimaxi.com/v1/token_plan/remains")
    }

    // MARK: - rawValue & allCases

    @Test
    func `rawValue round-trip`() {
        for region in MiniMaxRegion.allCases {
            #expect(MiniMaxRegion(rawValue: region.rawValue) == region)
        }
    }

    @Test
    func `allCases contains both regions`() {
        #expect(MiniMaxRegion.allCases.count == 2)
        #expect(MiniMaxRegion.allCases.contains(.international))
        #expect(MiniMaxRegion.allCases.contains(.china))
    }

    @Test
    func `invalid rawValue returns nil`() {
        #expect(MiniMaxRegion(rawValue: "invalid") == nil)
    }
}
