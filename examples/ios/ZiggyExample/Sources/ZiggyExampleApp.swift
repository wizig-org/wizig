import SwiftUI
import Ziggy

@main
struct ZiggyExampleApp: App {
    private let runtime = ZiggyRuntime(appName: "ziggy-example-ios")

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ziggy iOS Example")
                    .font(.title2.bold())
                Text("Registered plugins: \(runtime.plugins.count)")
                    .font(.body)
                Text("Runtime available: \(runtime.isAvailable ? "yes" : "no")")
                    .font(.body)
                Text("Echo: \((try? runtime.echo("hello")) ?? "unavailable")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Normal print") {
                    print("Hello from Swift!")
                    print(runtime)
                }

                ForEach(runtime.plugins, id: \.id) { plugin in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plugin.id).font(.headline)
                        Text("v\(plugin.version) • api \(plugin.apiVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
