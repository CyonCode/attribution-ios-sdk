import Foundation

public final class AttributionKit {
    public static let shared = AttributionKit()

    public weak var delegate: AttributionDelegate?

    private var config: AttributionConfig?
    private let engine: AttributionEngine

    public init() {
        self.engine = AttributionEngine()
    }

    public func configure(
        apiKey: String,
        appId: String,
        baseURL: String,
        distinctIdProvider: (() -> String?)? = nil
    ) {
        config = AttributionConfig(
            apiKey: apiKey,
            appId: appId,
            baseURL: baseURL,
            distinctIdProvider: distinctIdProvider
        )
    }

    public func performAttributionIfNeeded() {
        guard let config else { return }

        engine.performAttributionIfNeeded(config: config) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let attribution):
                self.delegate?.attribution(self, didComplete: attribution)
            case .failure(let error):
                self.delegate?.attribution(self, didFailWith: error)
            }
        }
    }

    public func cacheUTM(source: String?, medium: String?, campaign: String?, content: String?) {
        engine.cacheUTM(
            source: source,
            medium: medium,
            campaign: campaign,
            content: content
        )
    }

    public func handleUniversalLink(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

        let items = components.queryItems ?? []
        let queryMap = Dictionary(uniqueKeysWithValues: items.map { item in
            (item.name.lowercased(), item.value)
        })

        cacheUTM(
            source: queryMap["utm_source"] ?? queryMap["source"] ?? nil,
            medium: queryMap["utm_medium"] ?? queryMap["medium"] ?? nil,
            campaign: queryMap["utm_campaign"] ?? queryMap["campaign"] ?? nil,
            content: queryMap["utm_content"] ?? queryMap["content"] ?? nil
        )
    }
}
