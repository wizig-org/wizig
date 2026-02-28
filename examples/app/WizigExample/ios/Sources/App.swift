import SwiftUI
import Wizig

@main
struct WizigExampleApp: App {
    private let runtime = WizigRuntime(appName: "WizigExample")

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("WizigExample")
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
                Button("HELLO PRINT") {
                    print("🚀 hehheheheheheheehhehhheh 🚀")
                }

                Button("Throw Error") {
                    // no runtime
                    let error = NSError(
                        domain: "com.example.error", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "This is a test error."])
                    // nromally cause a iOS swift crash, but wizig should catch it and print it in the console instead
                    fatalError("This is a test error.")
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
