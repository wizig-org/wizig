import SwiftUI
import Ziggy

@main
struct ZiggyExampleApp: App {
    private let runtime = ZiggyRuntime(appName: "ZiggyExample")

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("ZiggyExample")
                    .font(.title2.bold())
                Text("Registered plugins: \(runtime.plugins.count)")
                Text("Runtime available: \(runtime.isAvailable ? "yes" : "no")")
                Text("Echo: \((try? runtime.echo("hello")) ?? "unavailable")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(runtime.plugins, id: \.id) { plugin in
                    Text(plugin.id)
                        .font(.footnote)
                }

                if let error = runtime.lastError {
                    Text("Runtime error: \(error)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
    }
}
