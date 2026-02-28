import SwiftUI
import Ziggy

@main
struct {{APP_TYPE_NAME}}App: App {
    private let runtime = ZiggyRuntime(appName: "{{APP_NAME}}")
    private let api = ZiggyGeneratedApi()

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("{{APP_NAME}}")
                    .font(.title2.bold())
                Text("Runtime available: \(runtime.isAvailable ? "yes" : "no")")
                Text("Generated API echo: \((try? api.echo("hello")) ?? "unavailable")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}
