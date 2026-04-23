import Foundation

public protocol AttributionDelegate: AnyObject {
    func attribution(_ kit: AttributionKit, didComplete result: AttributionResult)

    /// Retryable failure. Cached UTM is preserved; the next
    /// `performAttributionIfNeeded()` call will retry.
    func attribution(_ kit: AttributionKit, didFailWith error: AttributionError)
}

public extension AttributionDelegate {
    func attribution(_ kit: AttributionKit, didFailWith error: AttributionError) {}
}

public enum AttributionError: Error {
    case utmUploadFailed(underlying: Error)
}
