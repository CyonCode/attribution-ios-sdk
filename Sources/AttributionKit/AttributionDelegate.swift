public protocol AttributionDelegate: AnyObject {
    func attribution(_ kit: AttributionKit, didComplete result: AttributionResult)
}
