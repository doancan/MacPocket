import Foundation
import Darwin
import NetworkExtension
import Security
import MacPocketNetworkPolicy

/// The system owns this process. No host UI, capture or browsing code is linked into the provider.
final class MacPocketFilterDataProvider: NEFilterDataProvider {
    private var policy = AppNetworkPolicy()
    override func startFilter(completionHandler: @escaping @Sendable (Error?) -> Void) {
        do {
            guard let data = filterConfiguration.vendorConfiguration?["policy"] as? Data else {
                completionHandler(NSError(domain: "MacPocket.NetworkFilter", code: 1));return
            }
            policy = try AppNetworkPolicy.decode(data)
            let rule = NEFilterRule(networkRule: NENetworkRule(remoteNetworkEndpoint: nil, remotePrefix: 0, localNetworkEndpoint: nil, localPrefix: 0, protocol: .any, direction: .any), action: .filterData)
            apply(NEFilterSettings(rules: [rule], defaultAction: .allow), completionHandler: completionHandler)
        } catch { completionHandler(error) }
    }
    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        policy.action(for: ApplicationSigningIdentity.read(auditToken: flow.sourceAppAuditToken)) == .deny ? .drop() : .allow()
    }

}
NEProvider.startSystemExtensionMode()
dispatchMain()
