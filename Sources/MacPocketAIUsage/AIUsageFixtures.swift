#if DEBUG
import Foundation
import UsageCore

/// Available only to the explicitly named throwaway audit bundle. Never reads real credentials.
public enum AIUsageFixtures {
    public static var requested: Bool {
        Bundle.main.bundleIdentifier?.hasSuffix(".AIUsageAudit") == true && CommandLine.arguments.contains("--audit-ai-usage")
    }
    public static var profileSearchHome: URL {
        FileManager.default.temporaryDirectory.appending(path: "MacPocket.AIUsageAudit.ClaudeProfiles-\(ProcessInfo.processInfo.processIdentifier)")
    }
    @MainActor static func makeService() -> AIUsageService {
        let service = AIUsageService(defaults: .standard, cacheURL: nil) { account, _, _ in
            FixtureProvider(id: account.provider.providerID, percent: account.name == "Personal" ? 82 : 25,
                limited: account.provider == .grok)
        }
        var settings = AIUsageSettings()
        settings.accounts = [
            .init(name: "Personal", source: .claudeProfile(directory: "/tmp/macpocket-ai-fixture/personal", service: nil)),
            .init(name: "Work", source: .claudeProfile(directory: "/tmp/macpocket-ai-fixture/work", service: nil)),
            .init(name: "Dev", source: .codexFile(path: "/tmp/macpocket-ai-fixture/codex/auth.json")),
            .init(name: "Grok", source: .grokFile(path: "/tmp/macpocket-ai-fixture/grok/auth.json"))
        ]
        service.setSettings(settings)
        return service
    }
    private struct FixtureProvider: UsageProvider {
        let id: ProviderID
        let percent: Double
        let limited: Bool
        func fetch() async throws -> FetchOutcome {
            let limits = limited ? [] : [
                UsageLimit(id: "session", label: "Session", percentUsed: percent,
                    resetsAt: Date().addingTimeInterval(3_600), severity: .normal),
                UsageLimit(id: "weekly_all", label: "Weekly", percentUsed: percent / 2,
                    resetsAt: Date().addingTimeInterval(86_400), severity: .normal)
            ]
            return FetchOutcome(snapshot: UsageSnapshot(provider: id, fetchedAt: .now, limits: limits,
                status: limited ? .rateLimited(until: Date().addingTimeInterval(600), wait: 600) : .ok), requestSent: true)
        }
    }
}
#endif
