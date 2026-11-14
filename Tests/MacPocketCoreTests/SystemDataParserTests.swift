import Foundation
import Testing
@testable import MacPocketCore

@Suite struct SystemDataParserTests {
    @Test func humanSizesUseDecimalUnits() {
        #expect(SystemDataParsers.bytes(fromHumanSize: "1.5GB") == 1_500_000_000)
        #expect(SystemDataParsers.bytes(fromHumanSize: "4.7 GB") == 4_700_000_000)
        #expect(SystemDataParsers.bytes(fromHumanSize: "0B") == 0)
        #expect(SystemDataParsers.bytes(fromHumanSize: "3.5kB") == 3_500)
        #expect(SystemDataParsers.bytes(fromHumanSize: "12 TB") == 12_000_000_000_000)
        #expect(SystemDataParsers.bytes(fromHumanSize: "lots") == nil)
        #expect(SystemDataParsers.bytes(fromHumanSize: "5 parsecs") == nil)
        #expect(SystemDataParsers.bytes(fromHumanSize: "") == nil)
    }

    @Test func dockerUsageReadsReclaimableBytesAndNeverExceedsTheSize() {
        let output = """
        {"Active":"2","Reclaimable":"1.2GB (50%)","Size":"2.4GB","TotalCount":"5","Type":"Images"}
        {"Active":"1","Reclaimable":"0B (0%)","Size":"10MB","TotalCount":"1","Type":"Containers"}
        {"Active":"0","Reclaimable":"9GB (100%)","Size":"3GB","TotalCount":"2","Type":"Local Volumes"}
        {"Active":"0","Reclaimable":"500MB","Size":"500MB","TotalCount":"9","Type":"Build Cache"}
        not json
        {"Type":"Unknown","Size":"1GB"}
        """
        let usage = SystemDataParsers.dockerUsage(output)
        #expect(usage.map(\.kind) == [.images, .containers, .volumes, .buildCache])
        #expect(usage[0].reclaimableBytes == 1_200_000_000)
        #expect(usage[2].reclaimableBytes == 3_000_000_000)
    }

    @Test func ollamaListSkipsTheHeaderAndRejectsUnsafeNames() {
        let output = """
        NAME              ID              SIZE      MODIFIED
        llama3:latest     365c0bd3c000    4.7 GB    2 weeks ago
        qwen2.5-coder:7b  2b0496514337    4.7 GB    3 days ago
        bad name;rm       aaaaaaaaaaaa    1.0 GB    now
        """
        let models = SystemDataParsers.ollamaModels(output)
        #expect(models.map(\.name) == ["llama3:latest", "qwen2.5-coder:7b"])
        #expect(models[0].sizeBytes == 4_700_000_000)
    }

    /// Layout taken from ollama's `ListHandler`: tablewriter with four spaces of padding, `format.HumanBytes` sizes
    /// (decimal units, a space before the unit, integers from 10 up) and `-` as the size of cloud models.
    @Test func ollamaListMatchesTheLayoutTheToolActuallyPrints() {
        let output = """
        NAME                           ID              SIZE      MODIFIED
        llama3.2:latest                a80c4f17acd5    2.0 GB    3 days ago
        qwen2.5-coder:32b              b92d6a0bd47e    19 GB     2 weeks ago
        tiny:latest                    0123456789ab    500 B     Never
        gpt-oss:120b-cloud             f5ccd8a5e1bb    -         5 minutes ago
        hf.co/org/model-GGUF:Q4_K_M    abcdefabcdef    12 MB     About an hour ago
        """
        let models = SystemDataParsers.ollamaModels(output)
        #expect(models.map(\.name) == ["llama3.2:latest", "qwen2.5-coder:32b", "tiny:latest", "hf.co/org/model-GGUF:Q4_K_M"])
        #expect(models.map(\.sizeBytes) == [2_000_000_000, 19_000_000_000, 500, 12_000_000], "cloud models take no local space and are skipped")
    }

    @Test func ollamaManifestPathsFollowTheRegistryLayoutAndRefuseTraversal() {
        #expect(SystemDataParsers.ollamaManifestPath(for: "llama3:latest") == "manifests/registry.ollama.ai/library/llama3/latest")
        #expect(SystemDataParsers.ollamaManifestPath(for: "llama3") == "manifests/registry.ollama.ai/library/llama3/latest")
        #expect(SystemDataParsers.ollamaManifestPath(for: "user/model:7b") == "manifests/registry.ollama.ai/user/model/7b")
        #expect(SystemDataParsers.ollamaManifestPath(for: "hf.co/org/model-GGUF:Q4_K_M") == "manifests/hf.co/org/model-GGUF/Q4_K_M")
        #expect(SystemDataParsers.ollamaManifestPath(for: "../../etc/passwd:x") == nil)
        #expect(SystemDataParsers.ollamaManifestPath(for: "a/b/c/d:x") == nil)
        #expect(SystemDataParsers.ollamaManifestPath(for: "bad name") == nil)
    }

    @Test func exactModelSizesCountOnlyWhatDeletingTheModelFrees() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ollama-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        func manifest(_ model: String, _ layers: [(String, Int)]) throws {
            let path = try #require(SystemDataParsers.ollamaManifestPath(for: model))
            let file = root.appending(path: path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let list = layers.map { ["digest": "sha256:\($0.0)", "size": $0.1, "mediaType": "x"] }
            try JSONSerialization.data(withJSONObject: ["layers": Array(list.dropFirst()), "config": list[0]]).write(to: file)
        }
        try manifest("a:latest", [("config-a", 400), ("base", 1_000_000), ("only-a", 500_000)])
        try manifest("b:latest", [("config-b", 400), ("base", 1_000_000), ("only-b", 200_000)])
        let sizes = SystemDataParsers.ollamaExclusiveBytes(models: ["a:latest", "b:latest", "missing:latest"], modelsDirectory: root)
        #expect(sizes["a:latest"]?.exclusive == 500_400 && sizes["a:latest"]?.shared == 1_000_000)
        #expect(sizes["b:latest"]?.exclusive == 200_400)
        #expect(sizes["missing:latest"] == nil, "no manifest, so the size ollama printed is kept")
    }

    @Test func snapshotDatesAreExtractedFromTmutilOutput() {
        let output = """
        Snapshots for disk /:
        com.apple.TimeMachine.2026-11-01-120000.local
        com.apple.TimeMachine.2026-11-02-090500.local
        """
        #expect(SystemDataParsers.localSnapshotDates(output) == ["2026-11-01-120000", "2026-11-02-090500"])
        #expect(SystemDataParsers.localSnapshotDates("Snapshots for disk /:").isEmpty)
        #expect(SystemDataParsers.snapshotDate("2026-11-01-120000") != nil)
    }

    @Test func simulatorRuntimesAreReadFromTheRealJSONShape() {
        let json = """
        {"55C87D17-CC93-4CBF-BD1A-E576F74DFC6B":{"build":"24A434","deletable":true,"identifier":"55C87D17-CC93-4CBF-BD1A-E576F74DFC6B",
         "platformIdentifier":"com.apple.platform.iphonesimulator","runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0",
         "sizeBytes":8067000161,"state":"Ready","version":"27.0"},
         "not-a-uuid":{"runtimeIdentifier":"x","sizeBytes":1}}
        """
        let runtimes = SystemDataParsers.simulatorRuntimes(Data(json.utf8))
        #expect(runtimes.count == 1)
        #expect(runtimes[0].platform == "iphonesimulator")
        #expect(runtimes[0].sizeBytes == 8_067_000_161)
        #expect(runtimes[0].runtimeIdentifier.hasSuffix("iOS-27-0"))
    }

    @Test func simulatorDevicesCarryTheirSizeAndAvailability() {
        let json = """
        {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[
          {"udid":"AC3F48EB-2EDE-4471-8EAE-538698A57971","name":"iPhone 18 Pro","dataPath":"/Users/x/Library/Developer/CoreSimulator/Devices/AC3F48EB-2EDE-4471-8EAE-538698A57971/data",
           "dataPathSize":18337792,"isAvailable":true,"state":"Booted","lastBootedAt":"2026-11-01T10:00:00Z"},
          {"udid":"nope","dataPath":"/x"}]}}
        """
        let devices = SystemDataParsers.simulatorDevices(Data(json.utf8))
        #expect(devices.count == 1)
        #expect(devices[0].isBooted)
        #expect(devices[0].lastBooted != nil)
        #expect(devices[0].dataPathSize == 18_337_792)
    }

    @Test func garbageInputYieldsNothing() {
        #expect(SystemDataParsers.simulatorRuntimes(Data("garbage".utf8)).isEmpty)
        #expect(SystemDataParsers.simulatorDevices(Data("[]".utf8)).isEmpty)
        #expect(SystemDataParsers.dockerUsage("Cannot connect to the Docker daemon").isEmpty)
        #expect(SystemDataParsers.ollamaModels("").isEmpty)
    }
}

@Suite struct SystemDataSearchTests {
    @Test func turkishLettersAreFoundWithPlainOnesInEitherDirection() {
        #expect(SystemDataSearch.matches("kayit", in: ["Cargo kayıt defteri"]))
        #expect(SystemDataSearch.matches("KAYIT", in: ["Cargo kayıt defteri"]))
        #expect(SystemDataSearch.matches("kayıt", in: ["Cargo kayit defteri"]))
        #expect(SystemDataSearch.matches("istanbul", in: ["İstanbul Projesi"]))
        #expect(SystemDataSearch.matches("ISTANBUL", in: ["İstanbul Projesi"]))
        #expect(SystemDataSearch.matches("cagri sogus", in: ["Çağrı Şöğüş"]))
        #expect(SystemDataSearch.matches("cafe", in: ["Cafe\u{0301} (NFD)"]))
        #expect(SystemDataSearch.matches("日本", in: ["日本語フォルダ"]))
    }

    @Test func everyWordMustMatchAnywhereAndTheEmptyQueryMatchesAll() {
        #expect(SystemDataSearch.matches("cargo defteri", in: ["Cargo kayıt defteri"]))
        #expect(SystemDataSearch.matches("defteri cargo", in: ["Cargo kayıt defteri"]), "word order does not matter")
        #expect(!SystemDataSearch.matches("cargo docker", in: ["Cargo kayıt defteri"]))
        #expect(SystemDataSearch.matches("", in: ["anything"]) && SystemDataSearch.matches("   ", in: []))
        #expect(!SystemDataSearch.matches("x", in: []))
    }

    @Test func itemsAreFoundByTitleDetailGroupAndPath() {
        let item = SystemDataItem(id: "p", group: .projects, title: "node_modules — web", detail: "Bağımlılıklar", safety: .review,
                                  regeneration: .downloadsAgain, paths: ["/Users/me/Projeler/Çalışma/web/node_modules"], sizeBytes: 1,
                                  action: .removeFolder, projectPath: "/Users/me/Projeler/Çalışma/web")
        #expect(SystemDataSearch.matches("bagimliliklar", item: item))
        #expect(SystemDataSearch.matches("calisma", item: item), "found through the path")
        #expect(SystemDataSearch.matches("node_modules web", item: item))
        #expect(!SystemDataSearch.matches("docker", item: item))
    }
}
