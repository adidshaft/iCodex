import Foundation
import Combine

@MainActor
final class ModelsViewModel: ObservableObject {
    @Published var models: [CodexModel] = []
    @Published var config: CodexConfig?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                async let modelsReq = APIService.shared.fetchModels()
                async let configReq = APIService.shared.fetchConfig()
                let (modelsList, cfg) = try await (modelsReq, configReq)
                self.models = modelsList
                self.config = cfg
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isLoading = false
        }
    }
}
