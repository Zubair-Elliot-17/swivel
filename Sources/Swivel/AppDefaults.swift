import Foundation

/// Where settings live: QA runs (SWIVEL_QA=1) use their own suite, never the user's domain (Q2).
enum AppDefaults {
    static func suiteName(environment: [String: String]) -> String? {
        environment["SWIVEL_QA"] == "1" ? "dev.zubair.swivel.qa" : nil
    }

    static func make(environment: [String: String]) -> UserDefaults {
        // UserDefaults(suiteName:) is nil only for the app's own id or the global domain, never for this name.
        suiteName(environment: environment).map { UserDefaults(suiteName: $0)! } ?? .standard
    }
}
