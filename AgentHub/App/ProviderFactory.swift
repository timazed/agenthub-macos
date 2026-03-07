import Foundation

protocol ProviderFactory {
    var provider: AuthProvider { get }
    var capabilities: ProviderCapabilities { get }

    func makeRuntime() -> AssistantRuntime
    func makeAuthProviderClient(runtime: AssistantRuntime, paths: AppPaths) -> AuthProviderClient
}
