import Darwin
import Foundation

public enum WizigRuntimeError: Error, CustomStringConvertible {
    case ffiLibraryLoadFailed(String)
    case ffiSymbolMissing(String)
    case ffiCallFailed(function: String, status: Int32)
    case runtimeUnavailable
    case invalidUtf8

    public var description: String {
        switch self {
        case let .ffiLibraryLoadFailed(reason):
            return "failed to load Wizig FFI library: \(reason)"
        case let .ffiSymbolMissing(name):
            return "missing Wizig FFI symbol: \(name)"
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

private final class WizigFFI {
    typealias RuntimeNewFn = @convention(c) (
        UnsafePointer<UInt8>,
        Int,
        UnsafeMutablePointer<UnsafeMutableRawPointer?>?
    ) -> Int32

    typealias RuntimeFreeFn = @convention(c) (UnsafeMutableRawPointer?) -> Void

    typealias RuntimeEchoFn = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<UInt8>,
        Int,
        UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
        UnsafeMutablePointer<Int>?
    ) -> Int32

    typealias BytesFreeFn = @convention(c) (UnsafeMutablePointer<UInt8>?, Int) -> Void

    let runtimeNew: RuntimeNewFn
    let runtimeFree: RuntimeFreeFn
    let runtimeEcho: RuntimeEchoFn
    let bytesFree: BytesFreeFn

    private let libraryHandle: UnsafeMutableRawPointer

    private init(
        libraryHandle: UnsafeMutableRawPointer,
        runtimeNew: @escaping RuntimeNewFn,
        runtimeFree: @escaping RuntimeFreeFn,
        runtimeEcho: @escaping RuntimeEchoFn,
        bytesFree: @escaping BytesFreeFn
    ) {
        self.libraryHandle = libraryHandle
        self.runtimeNew = runtimeNew
        self.runtimeFree = runtimeFree
        self.runtimeEcho = runtimeEcho
        self.bytesFree = bytesFree
    }

    deinit {
        _ = dlclose(libraryHandle)
    }

    static func load(libraryPath: String?) throws -> WizigFFI {
        let pathCandidates: [String] = {
            if let libraryPath, !libraryPath.isEmpty {
                return [libraryPath]
            }

            var values = [String]()
            if let fromEnv = ProcessInfo.processInfo.environment["WIZIG_FFI_LIB"], !fromEnv.isEmpty {
                values.append(fromEnv)
            }
            values.append(contentsOf: ["libwizigffi.dylib", "wizigffi"])
            return values
        }()

        var lastError = "no candidate library path"

        for candidate in pathCandidates {
            _ = dlerror()
            guard let handle = dlopen(candidate, RTLD_NOW | RTLD_LOCAL) else {
                lastError = String(cString: dlerror())
                continue
            }

            do {
                let runtimeNew: RuntimeNewFn = try loadSymbol(handle, name: "wizig_runtime_new")
                let runtimeFree: RuntimeFreeFn = try loadSymbol(handle, name: "wizig_runtime_free")
                let runtimeEcho: RuntimeEchoFn = try loadSymbol(handle, name: "wizig_runtime_echo")
                let bytesFree: BytesFreeFn = try loadSymbol(handle, name: "wizig_bytes_free")

                return WizigFFI(
                    libraryHandle: handle,
                    runtimeNew: runtimeNew,
                    runtimeFree: runtimeFree,
                    runtimeEcho: runtimeEcho,
                    bytesFree: bytesFree
                )
            } catch {
                _ = dlclose(handle)
                throw error
            }
        }

        throw WizigRuntimeError.ffiLibraryLoadFailed(lastError)
    }

    private static func loadSymbol<T>(_ handle: UnsafeMutableRawPointer, name: String) throws -> T {
        _ = dlerror()
        guard let symbol = dlsym(handle, name) else {
            throw WizigRuntimeError.ffiSymbolMissing(name)
        }
        return unsafeBitCast(symbol, to: T.self)
    }
}

public final class WizigRuntime {
    public let plugins: [PluginDescriptor]
    public private(set) var lastError: WizigRuntimeError?

    private var ffi: WizigFFI?
    private var handle: UnsafeMutableRawPointer?

    public var isAvailable: Bool {
        handle != nil && ffi != nil && lastError == nil
    }

    public init(
        appName: String = "wizig-ios",
        plugins: [PluginDescriptor] = GeneratedPluginRegistrant.plugins,
        libraryPath: String? = nil
    ) {
        self.plugins = plugins

        do {
            let ffi = try WizigFFI.load(libraryPath: libraryPath)
            self.ffi = ffi

            var runtimeHandle: UnsafeMutableRawPointer?
            let status = try withUTF8Pointer(of: appName) { ptr, len in
                ffi.runtimeNew(ptr, len, &runtimeHandle)
            }

            guard status == WizigStatus.ok.rawValue, runtimeHandle != nil else {
                throw WizigRuntimeError.ffiCallFailed(function: "wizig_runtime_new", status: status)
            }
            self.handle = runtimeHandle
        } catch let error as WizigRuntimeError {
            lastError = error
        } catch {
            lastError = .ffiLibraryLoadFailed(error.localizedDescription)
        }
    }

    deinit {
        close()
    }

    public func close() {
        guard let ffi, let handle else { return }
        ffi.runtimeFree(handle)
        self.handle = nil
    }

    public func hasPlugin(_ id: String) -> Bool {
        plugins.contains { $0.id == id }
    }

    public func echo(_ input: String) throws -> String {
        guard let ffi, let handle else {
            throw lastError ?? .runtimeUnavailable
        }

        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let status = try withUTF8Pointer(of: input) { ptr, len in
            ffi.runtimeEcho(handle, ptr, len, &outPtr, &outLen)
        }

        guard status == WizigStatus.ok.rawValue else {
            throw WizigRuntimeError.ffiCallFailed(function: "wizig_runtime_echo", status: status)
        }

        guard let outPtr else {
            throw WizigRuntimeError.runtimeUnavailable
        }

        defer {
            ffi.bytesFree(outPtr, outLen)
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
