import SwiftUI
import Wizig

@main
struct {{APP_TYPE_NAME}}App: App {
    private let runtime = WizigRuntime(appName: "{{APP_NAME}}")
    private let api = WizigGeneratedApi()

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("{{APP_NAME}}")
                    .font(.title2.bold())
                Text("Runtime available: \(runtime.isAvailable ? "yes" : "no")")
                Text("Generated API echo: \((try? api.echo("hello")) ?? "unavailable")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Echo Zig") {
                    Task {
                        do {
                            try await api.echoZig("SwiftUI")
                        } catch {
                            print("Error calling echoZig: \(error)")
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}
