import Foundation

#if os(iOS) && canImport(AdServices)
import AdServices
#endif

final class AttributionEngine {
    private var attributionCompleted: Bool {
        get { userDefaults.bool(forKey: Keys.attributionCompleted) }
        set { userDefaults.set(newValue, forKey: Keys.attributionCompleted) }
    }

    private var cachedUTMSource: String {
        get { userDefaults.string(forKey: Keys.cachedUTMSource) ?? "" }
        set { userDefaults.set(newValue, forKey: Keys.cachedUTMSource) }
    }

    private var cachedUTMMedium: String {
        get { userDefaults.string(forKey: Keys.cachedUTMMedium) ?? "" }
        set { userDefaults.set(newValue, forKey: Keys.cachedUTMMedium) }
    }

    private var cachedUTMCampaign: String {
        get { userDefaults.string(forKey: Keys.cachedUTMCampaign) ?? "" }
        set { userDefaults.set(newValue, forKey: Keys.cachedUTMCampaign) }
    }

    private var cachedUTMContent: String {
        get { userDefaults.string(forKey: Keys.cachedUTMContent) ?? "" }
        set { userDefaults.set(newValue, forKey: Keys.cachedUTMContent) }
    }

    private let userDefaults: UserDefaults
    
    private let network: AttributionNetwork
    private let stateLock = NSLock()
    private var isRunning = false

    init(network: AttributionNetwork = AttributionNetwork(), userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.network = network
    }

    func performAttributionIfNeeded(
        config: AttributionConfig,
        completion: @escaping (Result<AttributionResult, AttributionError>) -> Void
    ) {
        stateLock.lock()
        if attributionCompleted || isRunning {
            stateLock.unlock()
            return
        }

        isRunning = true
        stateLock.unlock()

        if normalized(cachedUTMSource) != nil {
            resolveCachedUTM(config: config) { [weak self] resolution in
                guard let self else { return }
                switch resolution {
                case .resolved(let result):
                    self.finish(with: .success(result), completion: completion)
                case .uploadFailed(let error):
                    self.abortWithRetry(
                        error: .utmUploadFailed(underlying: error),
                        completion: completion
                    )
                case .noCache:
                    self.resolveFallbackAttribution(config: config, completion: completion)
                }
            }
            return
        }

        resolveFallbackAttribution(config: config, completion: completion)
    }

    func cacheUTM(source: String?, medium: String?, campaign: String?, content: String?) {
        var didCacheNewValue = false

        if let source = normalized(source) {
            cachedUTMSource = source
            didCacheNewValue = true
        }

        if let medium = normalized(medium) {
            cachedUTMMedium = medium
            didCacheNewValue = true
        }

        if let campaign = normalized(campaign) {
            cachedUTMCampaign = campaign
            didCacheNewValue = true
        }

        if let content = normalized(content) {
            cachedUTMContent = content
            didCacheNewValue = true
        }

        if didCacheNewValue {
            attributionCompleted = false
        }
    }

    private func resolveASAAttribution(
        config: AttributionConfig,
        attempt: Int,
        completion: @escaping (AttributionResult?) -> Void
    ) {
        #if os(iOS) && canImport(AdServices)
        let token: String
        do {
            token = try AAAttribution.attributionToken()
        } catch {
            completion(nil)
            return
        }

        let request = ASARequest(
            token: token,
            idfv: network.idfv(),
            appVersion: network.appVersion(),
            systemVersion: network.systemVersion(),
            deviceModel: network.deviceModel()
        )

        let delays: [TimeInterval] = [1, 2, 4]
        network.post(path: "/v1/attribution/asa", body: request, config: config) { [weak self] (result: Result<AttributionNetwork.ResponseEnvelope<AttributionResponse>, Error>) in
            guard let self else { return }

            switch result {
            case let .success(response):
                guard response.body.attributed == true else {
                    completion(nil)
                    return
                }
                completion(response.body.makeResult(rawPayload: response.rawPayload))
            case .failure:
                guard attempt < delays.count else {
                    completion(nil)
                    return
                }

                DispatchQueue.global().asyncAfter(deadline: .now() + delays[attempt]) {
                    self.resolveASAAttribution(config: config, attempt: attempt + 1, completion: completion)
                }
            }
        }

        #else
        completion(nil)
        #endif
    }

    private func resolveFingerprintMatch(
        config: AttributionConfig,
        completion: @escaping (AttributionResult?) -> Void
    ) {
        let request = MatchRequest(
            idfv: network.idfv(),
            ip: nil,
            userAgent: network.userAgent(appId: config.appId)
        )

        network.post(path: "/v1/attribution/match", body: request, config: config) { (result: Result<AttributionNetwork.ResponseEnvelope<AttributionResponse>, Error>) in
            switch result {
            case let .success(response):
                guard response.body.isMatched else {
                    completion(nil)
                    return
                }
                completion(response.body.makeResult(rawPayload: response.rawPayload))
            case .failure:
                completion(nil)
            }
        }
    }

    private func resolveCachedUTM(
        config: AttributionConfig,
        completion: @escaping (UTMResolution) -> Void
    ) {
        guard let source = normalized(cachedUTMSource) else {
            completion(.noCache)
            return
        }

        let request = UTMRequest(
            idfv: network.idfv(),
            utmSource: source,
            utmMedium: normalized(cachedUTMMedium),
            utmCampaign: normalized(cachedUTMCampaign),
            utmContent: normalized(cachedUTMContent)
        )

        network.post(path: "/v1/attribution/utm", body: request, config: config) { (result: Result<AttributionNetwork.ResponseEnvelope<AttributionResponse>, Error>) in
            switch result {
            case let .success(response):
                self.clearCachedUTM()
                completion(.resolved(response.body.makeResult(rawPayload: response.rawPayload)))
            case .failure(let error):
                completion(.uploadFailed(error))
            }
        }
    }

    private func resolveFallbackAttribution(
        config: AttributionConfig,
        completion: @escaping (Result<AttributionResult, AttributionError>) -> Void
    ) {
        resolveASAAttribution(config: config, attempt: 0) { [weak self] asaResult in
            guard let self else { return }

            if let asaResult {
                self.finish(with: .success(asaResult), completion: completion)
                return
            }

            self.resolveFingerprintMatch(config: config) { fingerprintResult in
                if let fingerprintResult {
                    self.finish(with: .success(fingerprintResult), completion: completion)
                    return
                }

                self.finish(
                    with: .success(AttributionResult(source: "organic")),
                    completion: completion
                )
            }
        }
    }

    private func finish(
        with result: Result<AttributionResult, AttributionError>,
        completion: @escaping (Result<AttributionResult, AttributionError>) -> Void
    ) {
        stateLock.lock()
        attributionCompleted = true
        isRunning = false
        stateLock.unlock()

        DispatchQueue.main.async {
            completion(result)
        }
    }

    private func abortWithRetry(
        error: AttributionError,
        completion: @escaping (Result<AttributionResult, AttributionError>) -> Void
    ) {
        stateLock.lock()
        isRunning = false
        stateLock.unlock()

        DispatchQueue.main.async {
            completion(.failure(error))
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func clearCachedUTM() {
        cachedUTMSource = ""
        cachedUTMMedium = ""
        cachedUTMCampaign = ""
        cachedUTMContent = ""
    }
}

private enum UTMResolution {
    case resolved(AttributionResult)
    case uploadFailed(Error)
    case noCache
}

private enum Keys {
    static let attributionCompleted = "ak_attribution_completed"
    static let cachedUTMSource = "ak_cached_utm_source"
    static let cachedUTMMedium = "ak_cached_utm_medium"
    static let cachedUTMCampaign = "ak_cached_utm_campaign"
    static let cachedUTMContent = "ak_cached_utm_content"
}

private struct ASARequest: Encodable {
    let token: String
    let idfv: String?
    let appVersion: String
    let systemVersion: String
    let deviceModel: String

    enum CodingKeys: String, CodingKey {
        case token
        case idfv
        case appVersion = "app_version"
        case systemVersion = "system_version"
        case deviceModel = "device_model"
    }
}

private struct MatchRequest: Encodable {
    let idfv: String?
    let ip: String?
    let userAgent: String?

    enum CodingKeys: String, CodingKey {
        case idfv
        case ip
        case userAgent = "user_agent"
    }
}

private struct UTMRequest: Encodable {
    let idfv: String?
    let utmSource: String
    let utmMedium: String?
    let utmCampaign: String?
    let utmContent: String?

    enum CodingKeys: String, CodingKey {
        case idfv
        case utmSource = "utm_source"
        case utmMedium = "utm_medium"
        case utmCampaign = "utm_campaign"
        case utmContent = "utm_content"
    }
}

private struct AttributionResponse: Decodable {
    let attributed: Bool?
    let matched: Bool?
    let source: String?
    let campaign: String?
    let medium: String?
    let content: String?
    let utmSource: String?
    let utmCampaign: String?
    let utmMedium: String?
    let utmContent: String?

    enum CodingKeys: String, CodingKey {
        case attributed
        case matched
        case source
        case campaign
        case medium
        case content
        case utmSource = "utm_source"
        case utmCampaign = "utm_campaign"
        case utmMedium = "utm_medium"
        case utmContent = "utm_content"
    }

    var isMatched: Bool {
        matched == true || attributed == true
    }

    func makeResult(rawPayload: [String: Any]?) -> AttributionResult {
        AttributionResult(
            source: source ?? utmSource ?? "organic",
            campaign: campaign ?? utmCampaign,
            medium: medium ?? utmMedium,
            content: content ?? utmContent,
            rawPayload: rawPayload
        )
    }
}
