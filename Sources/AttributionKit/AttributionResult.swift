import Foundation

public struct AttributionResult {
    public let source: String
    public let campaign: String?
    public let medium: String?
    public let content: String?
    public let isOrganic: Bool
    public let rawPayload: [String: Any]?

    public init(
        source: String,
        campaign: String? = nil,
        medium: String? = nil,
        content: String? = nil,
        rawPayload: [String: Any]? = nil
    ) {
        self.source = source
        self.campaign = campaign
        self.medium = medium
        self.content = content
        self.isOrganic = source.lowercased() == "organic"
        self.rawPayload = rawPayload
    }
}
