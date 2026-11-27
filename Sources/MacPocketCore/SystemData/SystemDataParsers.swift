import Foundation

/// Turns the output of the tools the scanner asks (`simctl`, `tmutil`, `docker`, `ollama`) into values.
/// Everything here is pure; the scanner decides what to do when a tool is missing or fails.
enum SystemDataParsers {
    struct SimulatorRuntime: Equatable {
        let identifier: String
        let version: String
        let build: String
        let platform: String
        let sizeBytes: Int64
        let state: String
        let deletable: Bool
        /// `com.apple.CoreSimulator.SimRuntime.iOS-27-2`, the key simulator devices are listed under.
        let runtimeIdentifier: String
    }

    struct SimulatorDevice: Equatable {
        let udid: String
        let name: String
        let runtimeIdentifier: String
        let dataPath: String
        let dataPathSize: Int64
        let isAvailable: Bool
        let isBooted: Bool
        let lastBooted: Date?
    }

    struct DockerUsage: Equatable {
        enum Kind: String { case images = "Images", containers = "Containers", volumes = "Local Volumes", buildCache = "Build Cache" }
        let kind: Kind
        let sizeBytes: Int64
        let reclaimableBytes: Int64
    }

    struct OllamaModel: Equatable {
        let name: String
        let sizeBytes: Int64
    }

    // MARK: Simulators

    static func simulatorRuntimes(_ data: Data) -> [SimulatorRuntime] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Any]] else { return [] }
        return root.compactMap { key, value -> SimulatorRuntime? in
            guard let identifier = (value["identifier"] as? String) ?? Optional(key), isUUID(identifier),
                  let runtime = value["runtimeIdentifier"] as? String,
                  let size = (value["sizeBytes"] as? NSNumber)?.int64Value else { return nil }
            let platform = (value["platformIdentifier"] as? String)?.split(separator: ".").last.map(String.init) ?? ""
            return SimulatorRuntime(identifier: identifier, version: value["version"] as? String ?? "", build: value["build"] as? String ?? "",
                                    platform: platform, sizeBytes: max(0, size), state: value["state"] as? String ?? "",
                                    deletable: value["deletable"] as? Bool ?? false, runtimeIdentifier: runtime)
        }.sorted { ($0.version, $0.identifier) < ($1.version, $1.identifier) }
    }

    static func simulatorDevices(_ data: Data) -> [SimulatorDevice] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let byRuntime = root["devices"] as? [String: [[String: Any]]] else { return [] }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        return byRuntime.flatMap { runtime, devices in
            devices.compactMap { device -> SimulatorDevice? in
                guard let udid = device["udid"] as? String, isUUID(udid), let path = device["dataPath"] as? String else { return nil }
                let booted = (device["lastBootedAt"] as? String).flatMap { formatter.date(from: $0) ?? plain.date(from: $0) }
                return SimulatorDevice(udid: udid, name: device["name"] as? String ?? "", runtimeIdentifier: runtime, dataPath: path,
                                       dataPathSize: max(0, (device["dataPathSize"] as? NSNumber)?.int64Value ?? 0),
                                       isAvailable: device["isAvailable"] as? Bool ?? true,
                                       isBooted: (device["state"] as? String) == "Booted", lastBooted: booted)
            }
        }.sorted { $0.udid < $1.udid }
    }

    static func isUUID(_ value: String) -> Bool {
        value.range(of: #"^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$"#, options: .regularExpression) != nil
    }

    // MARK: Time Machine

    /// `com.apple.TimeMachine.2026-11-01-120000.local` → `2026-11-01-120000`, the argument `tmutil` deletes
    /// by.
    static func localSnapshotDates(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            guard let range = line.range(of: #"\d{4}-\d{2}-\d{2}-\d{6}"#, options: .regularExpression) else { return nil }
            return String(line[range])
        }
    }

    static func snapshotDate(_ stamp: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.date(from: stamp)
    }

    // MARK: Docker

    /// Reads `docker system df --format '{{json .}}'`, one JSON object per line.
    static func dockerUsage(_ output: String) -> [DockerUsage] {
        output.split(whereSeparator: \.isNewline).compactMap { line -> DockerUsage? in
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let type = (object["Type"] as? String).flatMap(DockerUsage.Kind.init(rawValue:)),
                  let size = (object["Size"] as? String).flatMap(bytes(fromHumanSize:)) else { return nil }
            let reclaimable = (object["Reclaimable"] as? String)
                .flatMap { $0.split(separator: " ").first.map(String.init) }.flatMap(bytes(fromHumanSize:)) ?? 0
            return DockerUsage(kind: type, sizeBytes: size, reclaimableBytes: min(size, reclaimable))
        }
    }

    /// "1.2GB", "512 MB", "0B", "3.5kB" (decimal units, as Docker and Ollama print them).
    static func bytes(fromHumanSize text: String) -> Int64? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let numberText = String(trimmed.prefix { $0.isNumber || $0 == "." })
        let unit = trimmed.dropFirst(numberText.count).trimmingCharacters(in: .whitespaces).lowercased()
        guard let number = Double(numberText) else { return nil }
        let factor: Double
        switch unit {
        case "b": factor = 1
        case "kb": factor = 1_000
        case "mb": factor = 1_000_000
        case "gb": factor = 1_000_000_000
        case "tb": factor = 1_000_000_000_000
        default: return nil
        }
        let value = number * factor
        return value.isFinite && value < Double(Int64.max) ? Int64(value) : nil
    }

    // MARK: Ollama manifests

    struct OllamaLayer: Equatable { let digest: String; let size: Int64 }

    /// The layers (model weights, licence, parameters, config) a manifest lists, by digest.
    static func ollamaManifestLayers(_ data: Data) -> [OllamaLayer] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        let entries = ((root["layers"] as? [[String: Any]]) ?? []) + ((root["config"] as? [String: Any]).map { [$0] } ?? [])
        return entries.compactMap { entry in
            guard let digest = entry["digest"] as? String, let size = (entry["size"] as? NSNumber)?.int64Value, size >= 0 else { return nil }
            return OllamaLayer(digest: digest, size: size)
        }
    }

    /// `name:tag`, `namespace/name:tag` or `host/namespace/name:tag` → the manifest's path under the models
    /// folder.
    static func ollamaManifestPath(for model: String) -> String? {
        guard isValidModelName(model) else { return nil }
        var name = model, tag = "latest"
        if let colon = name.lastIndex(of: ":"), !name[colon...].contains("/") {
            tag = String(name[name.index(after: colon)...])
            name = String(name[..<colon])
        }
        let parts = name.split(separator: "/").map(String.init)
        guard !parts.isEmpty, parts.count <= 3, !parts.contains(where: { $0 == ".." || $0.isEmpty }), tag != ".." else { return nil }
        let host: String, namespace: String, base: String
        switch parts.count {
        case 1: (host, namespace, base) = ("registry.ollama.ai", "library", parts[0])
        case 2: (host, namespace, base) = ("registry.ollama.ai", parts[0], parts[1])
        default: (host, namespace, base) = (parts[0], parts[1], parts[2])
        }
        return "manifests/\(host)/\(namespace)/\(base)/\(tag)"
    }

    /// Bytes deleting each model frees: its layers that no other listed model uses. `shared` counts layers
    /// kept alive by another model. Models without a readable manifest are absent and keep the size `ollama
    /// list` printed.
    static func ollamaExclusiveBytes(models: [String], modelsDirectory: URL) -> [String: (exclusive: Int64, shared: Int64)] {
        var layersByModel: [String: [OllamaLayer]] = [:]
        for model in models {
            guard let path = ollamaManifestPath(for: model),
                  let data = try? Data(contentsOf: modelsDirectory.appending(path: path)) else { continue }
            let layers = ollamaManifestLayers(data)
            if !layers.isEmpty { layersByModel[model] = layers }
        }
        var users: [String: Int] = [:]
        for layers in layersByModel.values { for digest in Set(layers.map(\.digest)) { users[digest, default: 0] += 1 } }
        return layersByModel.mapValues { layers in
            var unique: [String: Int64] = [:]
            for layer in layers { unique[layer.digest] = layer.size }
            var exclusive: Int64 = 0, shared: Int64 = 0
            for (digest, size) in unique { if users[digest] == 1 { exclusive += size } else { shared += size } }
            return (exclusive, shared)
        }
    }

    // MARK: Ollama

    /// Reads `ollama list`: NAME  ID  SIZE  MODIFIED, columns separated by two or more spaces.
    static func ollamaModels(_ output: String) -> [OllamaModel] {
        output.split(whereSeparator: \.isNewline).dropFirst().compactMap { line -> OllamaModel? in
            let columns = line.components(separatedBy: "  ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard columns.count >= 3, isValidModelName(columns[0]), let size = bytes(fromHumanSize: columns[2]) else { return nil }
            return OllamaModel(name: columns[0], sizeBytes: size)
        }
    }

    static func isValidModelName(_ name: String) -> Bool {
        name.range(of: #"^[A-Za-z0-9][A-Za-z0-9._:/@-]{0,200}$"#, options: .regularExpression) != nil
    }
}
