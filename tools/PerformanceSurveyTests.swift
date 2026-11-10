import AppKit
import Combine
import CoreGraphics
import Darwin
import SwiftUI
import Synchronization
import XCTest
@testable import MacPocketCore
@testable import MacPocketApp

@MainActor private final class SurveyWeakImage {
    weak var value: NSImage?
    init(_ value: NSImage) { self.value = value }
}

@MainActor final class PerformanceSurveyTests: XCTestCase {
    private var root: URL!
    private var report: [String: Any] = [:]

    private func phase(_ name: String) {
        print("SURVEY_PHASE", name)
        try? JSONSerialization.data(withJSONObject: ["phase":name,"pid":getpid()]).write(to: root.appendingPathComponent("progress.json"))
    }

    private func stats(_ samples: [Double]) -> [String: Any] {
        let sorted = samples.sorted()
        return ["count":samples.count,"medianMS":sorted[sorted.count / 2],"p95MS":sorted[Int(Double(sorted.count - 1) * 0.95)],"samplesMS":samples]
    }

    private func time(_ body: () throws -> Void) rethrows -> Double {
        let start = ProcessInfo.processInfo.systemUptime
        try body()
        return (ProcessInfo.processInfo.systemUptime - start) * 1000
    }

    private func cpuMS() -> Double {
        var value = rusage(); getrusage(RUSAGE_SELF, &value)
        return Double(value.ru_utime.tv_sec + value.ru_stime.tv_sec) * 1000
            + Double(value.ru_utime.tv_usec + value.ru_stime.tv_usec) / 1000
    }

    private func onMainThread() -> Bool { Thread.isMainThread }

    private func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    private func residentBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to:&info) { pointer in
            pointer.withMemoryRebound(to:integer_t.self,capacity:Int(count)) { task_info(mach_task_self_,task_flavor_t(TASK_VM_INFO),$0,&count) }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }

    private func service(_ archive: ClipboardArchive) -> ClipboardService {
        let suite = "MacPocket.PerformanceSurvey." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        var settings = ClipboardSettings(); settings.enabled = true; settings.retentionDays = nil
        settings.save(to: defaults)
        addTeardownBlock {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            await MainActor.run { NSPasteboard(name: .init(suite)).releaseGlobally() }
        }
        return ClipboardService(defaults: defaults, archive: archive, pasteboard: NSPasteboard(name: .init(suite)))
    }

    func testMeasureAllFiveAreas() async throws {
        root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MACPOCKET_SURVEY_OUTPUT"]!)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = root.appendingPathComponent("fixtures")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let requestedAreas = ProcessInfo.processInfo.environment["MACPOCKET_SURVEY_AREAS"].map { Set($0.split(separator:",").map(String.init)) }
        if requestedAreas != nil, let data = try? Data(contentsOf:root.appendingPathComponent("report.json")),
           let previous = try? JSONSerialization.jsonObject(with:data) as? [String:Any] { report = previous }
        report["configuration"] = "Release XCTest, -O, measurement-only body counters in detached checkout"
        report["sourceCommit"] = ProcessInfo.processInfo.environment["MACPOCKET_SURVEY_SOURCE"] ?? "unknown"
        report["generalPasteboardAccess"] = false
        report["userArchivesAccess"] = false
        _ = NSApplication.shared
        let previousArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = previousArguments
        for module in PocketModule.allCases { arguments[module.availabilityKey] = false }
        for kind in ResourceAlertKind.allCases { arguments[ResourceAlertSettings.enabledKey(kind)] = false }
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain) }
        for (name, operation) in [
            ("disk", { try await self.measureDisk(fixture) }),
            ("search", { try await self.measureSearch() }),
            ("images", { try await self.measureImages(fixture) }),
            ("images-detailed", { try await self.measureImages(fixture,detailed:true) }),
            ("sensors", { try await self.measureSensors() }),
            ("ui", { try await self.measureUI(fixture) })
        ] {
            if let requestedAreas, !requestedAreas.contains(name) { continue }
            phase(name)
            do { try await operation() }
            catch { report[name] = ["error":String(describing: error)] }
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]).write(to: root.appendingPathComponent("report.json"))
        }
        phase("complete")
    }

    private func measureDisk(_ fixture: URL) async throws {
        var rows: [[String: Any]] = []
        for (count, length) in [(200,200), (1000,200), (200,20_000), (1000,20_000)] {
            let items = (0..<count).map { ClipboardItem(content: .text("Fixture \($0) " + String(repeating: "x", count:length)), copiedAt: Date(timeIntervalSince1970: 1_800_000_000)) }
            let archive = ClipboardArchive(directory: fixture.appendingPathComponent("disk-\(count)-\(length)"))
            try archive.save(ClipboardHistory(items:items))
            let clipboard = service(archive); clipboard.loadStoredHistory()
            var load: [Double] = [], save: [Double] = [], queueDelay: [Double] = [], unchanged: [Double] = []
            for index in 0..<12 {
                let loadMS = time { clipboard.loadStoredHistory() }
                clipboard.setPinned(index.isMultiple(of: 2), clipboard.history.items[0])
                let scheduled = ProcessInfo.processInfo.systemUptime
                var probe: Double?
                DispatchQueue.main.async { probe = (ProcessInfo.processInfo.systemUptime - scheduled) * 1000 }
                let saveMS = time { clipboard.flushSave() }
                while probe == nil { await Task.yield() }
                let cleanMS = time { clipboard.flushSave() }
                if index >= 2 { load.append(loadMS); save.append(saveMS); queueDelay.append(probe!); unchanged.append(cleanMS) }
            }
            let bytes = try FileManager.default.attributesOfItem(atPath: archive.historyFile.path)[.size] as! NSNumber
            rows.append(["items":count,"charactersPerItem":length,"fileBytes":bytes.intValue,"load":stats(load),
                "changedSave":stats(save),"mainQueueProbeDelay":stats(queueDelay),"unchangedFlush":stats(unchanged),"mainThread":onMainThread()])
        }
        report["disk"] = rows
    }

    private func measureSearch() async throws {
        var rows: [[String: Any]] = []
        for (count, length) in [(200,200), (1000,200), (200,20_000), (1000,20_000)] {
            let items = (0..<count).map { index in
                ClipboardItem(content:.text("İstanbul fixture \(index) " + String(repeating:"x",count:length)), copiedAt:Date(timeIntervalSince1970:1_800_000_000),sourceName:"FixtureApp",pinned:index.isMultiple(of:10))
            }
            let history = ClipboardHistory(items:items)
            for query in ["", "fixture", "ıstanbul", "missing-token"] {
                var samples:[Double] = [], checksum = 0
                for index in 0..<7 {
                    let elapsed = time { checksum += history.search(query).count }
                    if index > 0 { samples.append(elapsed) }
                }
                rows.append(["items":count,"charactersPerItem":length,"query":query,"timing":stats(samples),"checksum":checksum])
            }
        }
        report["search"] = rows
    }

    private func imageData(seed: Int, detailed: Bool) throws -> Data {
        let width = 3840, height = 2160
        let context = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        if detailed {
            let bytes = context.data!.assumingMemoryBound(to:UInt8.self)
            var random = UInt64(seed + 1) * 1234567
            for pixel in 0..<(width * height) {
                random ^= random << 13; random ^= random >> 7; random ^= random << 17
                let offset = pixel * 4
                bytes[offset] = UInt8(random & 15) * 17
                bytes[offset+1] = UInt8((random >> 4) & 7) * 34
                bytes[offset+2] = 127; bytes[offset+3] = 255
            }
        } else {
            context.setFillColor(CGColor(red:CGFloat(seed+1)/10,green:0.4,blue:0.7,alpha:1)); context.fill(CGRect(x:0,y:0,width:width,height:height))
            context.setFillColor(CGColor(red:0.9,green:0.2,blue:0.3,alpha:1)); context.fill(CGRect(x:seed*20,y:100,width:400,height:800))
        }
        return try XCTUnwrap(NSBitmapImageRep(cgImage:context.makeImage()!).representation(using:.png,properties:[:]))
    }

    private func draw(_ image: NSImage, size: Int = 36) {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
        image.draw(in:NSRect(x:0,y:0,width:size,height:size)); NSGraphicsContext.restoreGraphicsState()
    }

    private func measureImages(_ fixture: URL, detailed: Bool = false) async throws {
        let archive = ClipboardArchive(directory:fixture.appendingPathComponent("images"))
        var refs:[ClipboardImageReference] = [], diskBytes = 0
        for index in 0..<8 {
            let data = try autoreleasepool { try imageData(seed:index,detailed:detailed) }
            XCTAssertLessThanOrEqual(data.count, ClipboardSettings().maximumImageBytes)
            let name = String(format:"%016x.png",index+1)
            _ = try archive.storeImage(data,named:name); diskBytes += data.count
            refs.append(ClipboardImageReference(fileName:name,pixelWidth:3840,pixelHeight:2160,byteCount:data.count))
        }
        let clipboard = service(archive)
        try archive.save(ClipboardHistory(items:refs.map { ClipboardItem(content:.image($0),copiedAt:Date()) }))
        clipboard.loadStoredHistory()
        try await Task.sleep(for:.milliseconds(300))
        let before = footprint()
        let residentBefore = residentBytes()
        var steps:[[String:Any]] = []
        var firstIDs:[ObjectIdentifier] = []
        var weakImages:[SurveyWeakImage] = []
        for reference in refs {
            let elapsed = autoreleasepool {
                time {
                    let image = clipboard.image(for:reference)!
                    weakImages.append(SurveyWeakImage(image))
                    firstIDs.append(ObjectIdentifier(image)); draw(image)
                }
            }
            await Task.yield()
            steps.append(["loadedImages":steps.count+1,"footprintBytes":footprint(),"readAnd36pxDrawMS":elapsed])
        }
        try await Task.sleep(for:.milliseconds(300))
        let cached = footprint()
        let residentCached = residentBytes()
        let hits = refs.enumerated().filter { index, reference in ObjectIdentifier(clipboard.image(for:reference)!) == firstIDs[index] }.count
        let cache = Mirror(reflecting:clipboard).children.first { $0.label == "imageCache" }?.value as? NSCache<NSString,NSImage>
        var tiffBytes = 0
        let fullRepresentationMS = time {
            for reference in refs {
                autoreleasepool { tiffBytes += clipboard.image(for:reference)?.tiffRepresentation?.count ?? 0 }
            }
        }
        let fullFootprint = footprint(), fullResident = residentBytes()
        clipboard.eraseEverything()
        try await Task.sleep(for:.milliseconds(300))
        report[detailed ? "imagesDetailed" : "images"] = ["images":refs.count,"width":3840,"height":2160,"previewSize":36,"compressedBytes":diskBytes,
            "baselineFootprintBytes":before,"cachedFootprintBytes":cached,"afterClearFootprintBytes":footprint(),
            "baselineResidentBytes":residentBefore,"cachedResidentBytes":residentCached,"afterClearResidentBytes":residentBytes(),
            "fullRepresentationFootprintBytes":fullFootprint,"fullRepresentationResidentBytes":fullResident,
            "fullRepresentationMS":fullRepresentationMS,"generatedTIFFBytes":tiffBytes,
            "imagesStillAliveAfterClear":weakImages.filter { $0.value != nil }.count,
            "cacheIdentityHits":hits,"countLimit":cache?.countLimit ?? -1,"totalCostLimit":cache?.totalCostLimit ?? -1,
            "steps":steps,"input":detailed ? "deterministic 128-color noise" : "flat-color rectangles",
            "scope":"actual service image cache plus NSImage 36px raster draw; not full SwiftUI list"]
    }

    private func measureSensors() async throws {
        var rows:[[String:Any]] = []
        func measure(_ name:String, _ body:()->Int) {
            var wall:[Double] = [], cpu:[Double] = []; var readable = 0
            for index in 0..<14 {
                let startedCPU = cpuMS()
                let elapsed = time { readable = body() }
                let cpuElapsed = cpuMS() - startedCPU
                if index >= 2 { wall.append(elapsed); cpu.append(cpuElapsed) }
            }
            rows.append(["component":name,"wall":stats(wall),"processCPU":stats(cpu),"readableValues":readable])
        }
        let temperature = TemperatureSensor(), gpu = GPUSampler(), fan = FanSensor()
        var network = NetworkSampler(), disk = DiskIOSampler()
        measure("temperature") { temperature.sample()?.count ?? 0 }
        measure("gpu") { gpu.sample() == nil ? 0 : 1 }
        measure("fans") { fan.sample()?.count ?? 0 }
        measure("powerSMC") { let value = fan.power(); return [value.system,value.input].compactMap { $0 }.count }
        measure("networkCounters") { _ = network.sample(); return 1 }
        measure("diskIO") { _ = disk.sample(); return 1 }
        let monitor = SystemMonitor()
        var wall:[Double] = [], cpu:[Double] = []
        for index in 0..<14 {
            let start = ProcessInfo.processInfo.systemUptime, startedCPU = cpuMS()
            _ = try await monitor.snapshot()
            if index >= 2 { wall.append((ProcessInfo.processInfo.systemUptime-start)*1000); cpu.append(cpuMS()-startedCPU) }
        }
        report["sensors"] = ["components":rows,"wholeSnapshotWall":stats(wall),"wholeSnapshotProcessCPU":stats(cpu),"pingEnabled":false,
            "scope":"live read-only Mac Studio hardware; process CPU includes concurrent XCTest/runtime activity"]
    }

    private func snapshot(_ cpu: Int) throws -> SystemSnapshot {
        try JSONDecoder().decode(SystemSnapshot.self,from:Data("{\"capturedAt\":\(cpu),\"hardwareModel\":\"Fixture\",\"logicalCPUCount\":1,\"cpuUserPercent\":\(cpu),\"cpuSystemPercent\":2,\"cpuIdlePercent\":\(98-cpu),\"physicalMemoryBytes\":1024,\"freeMemoryBytes\":768,\"wiredMemoryBytes\":100,\"compressedMemoryBytes\":0,\"uptimeSeconds\":100,\"thermalState\":\"nominal\",\"volumes\":[],\"power\":{\"source\":\"AC\",\"batteryPresent\":false,\"lowPowerMode\":false}}".utf8))
    }

    private func measureUI(_ fixture: URL) async throws {
        let snapshots = try (0..<21).map { try snapshot($0) }
        var rows:[[String:Any]] = []
        for page in ["settings-general","settings-monitoring","tools"] {
            let model = PocketModel(startMonitoring:false,historyStore:PowerHistoryStore(url:fixture.appendingPathComponent(page+".json")))
            model.system = snapshots[0]
            let content:AnyView
            if page == "tools" { content = AnyView(ToolsHubView(model:model)) }
            else {
                PocketSettingsNavigation.shared.section = page == "settings-general" ? .general : .monitoring
                content = AnyView(PocketSettingsView(model:model,loginItem:LoginItemController()))
            }
            let window = NSWindow(contentRect:NSRect(x:0,y:0,width:1100,height:760),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView:content); window.contentView = host; window.orderFrontRegardless()
            try await Task.sleep(for:.milliseconds(800)); host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            PerformanceSurveyCounters.reset()
            let idleStart = ProcessInfo.processInfo.systemUptime, idleCPUStart = cpuMS()
            for _ in 0..<20 { try await Task.sleep(for:.milliseconds(80)); host.layoutSubtreeIfNeeded(); window.displayIfNeeded() }
            let idleMS = (ProcessInfo.processInfo.systemUptime-idleStart)*1000, idleCPU = cpuMS()-idleCPUStart
            let idle = PerformanceSurveyCounters.snapshot()
            PerformanceSurveyCounters.reset()
            // PocketModel is @Observable: tracking is armed before each assignment and counted.
            let notificationCount = Mutex(0)
            let updateStart = ProcessInfo.processInfo.systemUptime, updateCPUStart = cpuMS()
            for index in 1...20 {
                withObservationTracking { _ = model.system } onChange: { notificationCount.withLock { $0 += 1 } }
                model.system = snapshots[index]
                try await Task.sleep(for:.milliseconds(80)); host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            }
            let updateMS = (ProcessInfo.processInfo.systemUptime-updateStart)*1000, updateCPU = cpuMS()-updateCPUStart
            rows.append(["page":page,"systemAssignments":20,"systemChangeNotifications":notificationCount.withLock { $0 },"idleBodyEvaluations":idle,
                "idleElapsedMS":idleMS,"idleProcessCPUMS":idleCPU,"updateElapsedMS":updateMS,"updateProcessCPUMS":updateCPU,
                "estimatedExtraProcessCPUPerAssignmentMS":max(0,(updateCPU-idleCPU*updateMS/idleMS)/20),
                "cpuUpdateBodyEvaluations":PerformanceSurveyCounters.snapshot(),"windowVisible":window.isVisible])
            window.close()
            try await Task.sleep(for:.milliseconds(100))
        }
        report["ui"] = ["measurements":rows,"scope":"actual source views with body-entry counters in measurement-only checkout; 20 CPU-only assignments at 80ms; not normal 2s cadence"]
    }
}
