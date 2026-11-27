import Darwin

/// Virtualized Macs (such as GitHub's hosted runners) have no power model and no on-device Vision text
/// recognition, so tests that need real hardware skip those checks there.
enum TestEnvironment {
    static let isVirtualMachine: Bool = {
        var present: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("kern.hv_vmm_present", &present, &size, nil, 0) == 0 && present == 1
    }()
}
