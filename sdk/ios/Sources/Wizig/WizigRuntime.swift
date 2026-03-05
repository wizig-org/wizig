import WizigFFI
import Foundation

public enum WizigRuntimeError: Error, CustomStringConvertible {
    case ffiCallFailed(function: String, status: Int32)
    case runtimeUnavailable
    case invalidUtf8

    public var description: String {
        switch self {
        case let .ffiCallFailed(function, status):
            return "FFI call failed: \(function) returned status \(status)"
        case .runtimeUnavailable:
            return "runtime is unavailable"
        case .invalidUtf8:
            return "FFI returned non-UTF-8 output"
        }
    }
}

private enum WizigStatus: Int32 {
    case ok = 0
}

public final class WizigRuntime {
    public let plugins: [PluginDescriptor]
    public private(set) var lastError: WizigRuntimeError?

    private var handle: OpaquePointer?

    public var isAvailable: Bool {
        handle != nil && lastError == nil
    }

    public init(
        appName: String = "wizig-ios",
        plugins: [PluginDescriptor] = GeneratedPluginRegistrant.plugins
    ) {
        self.plugins = plugins

        do {
            var runtimeHandle: OpaquePointer?
            let status = try withUTF8Pointer(of: appName) { ptr, len in
                wizig_runtime_new(ptr, len, &runtimeHandle)
            }

            guard status == WizigStatus.ok.rawValue, runtimeHandle != nil else {
                throw WizigRuntimeError.ffiCallFailed(function: "wizig_runtime_new", status: status)
            }
            self.handle = runtimeHandle
        } catch let error as WizigRuntimeError {
            lastError = error
        } catch {
            lastError = .ffiCallFailed(function: "wizig_runtime_new", status: -1)
        }
    }

    deinit {
        close()
    }

    public func close() {
        guard let handle else { return }
        wizig_runtime_free(handle)
        self.handle = nil
    }

    public func hasPlugin(_ id: String) -> Bool {
        plugins.contains { $0.id == id }
    }

    public func echo(_ input: String) throws -> String {
        guard let handle else {
            throw lastError ?? .runtimeUnavailable
        }

        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let status = try withUTF8Pointer(of: input) { ptr, len in
            wizig_runtime_echo(handle, ptr, len, &outPtr, &outLen)
        }

        guard status == WizigStatus.ok.rawValue else {
            throw WizigRuntimeError.ffiCallFailed(function: "wizig_runtime_echo", status: status)
        }

        guard let outPtr else {
            throw WizigRuntimeError.runtimeUnavailable
        }

        defer {
            wizig_bytes_free(outPtr, outLen)
        }

        let data = Data(bytes: outPtr, count: outLen)
        guard let value = String(data: data, encoding: .utf8) else {
            throw WizigRuntimeError.invalidUtf8
        }

        return value
    }

    private func withUTF8Pointer<T>(
        of value: String,
        _ body: (UnsafePointer<UInt8>, Int) throws -> T
    ) throws -> T {
        let bytes = Array(value.utf8)
        if bytes.isEmpty {
            var placeholder: UInt8 = 0
            return try withUnsafePointer(to: &placeholder) { ptr in
                try body(ptr, 0)
            }
        }

        return try bytes.withUnsafeBufferPointer { buffer in
            try body(buffer.baseAddress!, buffer.count)
        }
    }
}
