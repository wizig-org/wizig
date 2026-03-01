import SwiftUI
import Wizig

@main
struct {{APP_TYPE_NAME}}App: App {
    private let api = try? WizigGeneratedApi()

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("{{APP_NAME}}")
                    .font(.title2.bold())
                Text("Runtime available: \(api != nil ? "yes" : "no")")
                Text("Generated API echo: \(api.flatMap { try? $0.echo("hello") } ?? "unavailable")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}
