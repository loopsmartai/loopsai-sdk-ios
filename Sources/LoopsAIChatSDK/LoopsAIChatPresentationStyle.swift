import UIKit

/// How ``LoopsAIChat/present(from:config:style:delegate:)`` shows the chat:
/// full-screen, a configurable bottom sheet, or pushed onto a nav stack.
public enum LoopsAIChatPresentationStyle {
    case fullScreen
    case sheet(LoopsAIChatSheetConfig = .default)
    case push
}

public struct LoopsAIChatSheetConfig {
    public let detents: [UISheetPresentationController.Detent]
    public let prefersGrabberVisible: Bool
    public let isInteractiveDismissEnabled: Bool

    public init(
        detents: [UISheetPresentationController.Detent] = [.large()],
        prefersGrabberVisible: Bool = false,
        isInteractiveDismissEnabled: Bool = true
    ) {
        self.detents = detents
        self.prefersGrabberVisible = prefersGrabberVisible
        self.isInteractiveDismissEnabled = isInteractiveDismissEnabled
    }

    public static let `default` = LoopsAIChatSheetConfig()

    public static let locked = LoopsAIChatSheetConfig(
        detents: [.large()],
        prefersGrabberVisible: false,
        isInteractiveDismissEnabled: false
    )

    public static let interactive = LoopsAIChatSheetConfig(
        detents: [.large(), .medium()],
        prefersGrabberVisible: true,
        isInteractiveDismissEnabled: true
    )
}
