import Foundation

enum HistoryConfig {
    /// Latest release manifest from your public data repo (see crime-near-me-data/README.md).
    static let manifestURL = "https://github.com/YOUR_GITHUB_USERNAME/crime-near-me-data/releases/latest/download/manifest.json"

    static var isConfigured: Bool { !manifestURL.contains("YOUR_GITHUB_USERNAME") }
}

/// History is free for now. To make it a paid extra later, add a StoreKit purchase
/// and return whether it has been bought here. Everything else already checks this.
enum HistoryAccess {
    static var isUnlocked: Bool { true }
}
