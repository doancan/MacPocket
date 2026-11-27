import Foundation

public struct ProcessOutput {
    public let exitCode: Int32?
    public let output: String

    public init(exitCode: Int32?, output: String) {
        self.exitCode = exitCode
        self.output = output
    }
}

public enum ProcessRunner {
    /// How long a command may ignore SIGTERM before it is killed.
    public static let killGrace: TimeInterval = 2

    public static func run(executable: URL, arguments: [String], timeout: TimeInterval,
                           captureOutput: Bool = false) async -> ProcessOutput {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.currentDirectoryURL = FileManager.default.temporaryDirectory
                process.standardInput = FileHandle.nullDevice
                let pipe = Pipe()
                process.standardOutput = captureOutput ? pipe : FileHandle.nullDevice
                process.standardError = captureOutput ? pipe : FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: ProcessOutput(exitCode: nil, output: ""))
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    guard process.isRunning else { return }
                    process.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + killGrace) {
                        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    }
                }
                let data = captureOutput ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
                process.waitUntilExit()
                let code = process.terminationReason == .exit ? process.terminationStatus : nil
                continuation.resume(returning: ProcessOutput(exitCode: code, output: String(decoding: data, as: UTF8.self)))
            }
        }
    }

    public static func start(executable: URL, arguments: [String]) -> Process? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return process
        } catch {
            return nil
        }
    }
}
