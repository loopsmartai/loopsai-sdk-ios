import Foundation

/// Context handed to the chat runtime: the product the user is viewing
/// (`productContext`) and what's known about the user (`userContext`). Pass it
/// at launch via ``LoopsAIChatConfig`` or update live with
/// ``LoopsAIChatViewController/updateContext(_:)``.
public struct LoopsAIChatContext: Sendable {
    public let productContext: [String: String]?
    public let userContext: [String: String]?

    public init(
        productContext: [String: String]? = nil,
        userContext: [String: String]? = nil
    ) {
        self.productContext = productContext
        self.userContext = userContext
    }

    internal func toPayload() -> [String: Any] {
        var payload: [String: Any] = [:]
        if let productContext { payload["productContext"] = productContext }
        if let userContext { payload["userContext"] = userContext }
        return payload
    }
}
