/// Exact IDs and helpers separated from an installed ID by a dot or hyphen, ignoring case.
/// Lookup work depends on the candidate's separators rather than the number of installed applications.
struct InstalledBundleIndex {
    let identifiers: Set<String>

    init(_ identifiers: Set<String>) {
        self.identifiers = Set(identifiers.map { $0.lowercased() })
    }

    func containsApplicationOrHelper(_ candidate: String) -> Bool {
        guard !identifiers.isEmpty else { return false }
        let candidate = candidate.lowercased()
        if identifiers.contains(candidate) { return true }
        for index in candidate.indices where candidate[index] == "." || candidate[index] == "-" {
            if identifiers.contains(String(candidate[..<index])) { return true }
        }
        return false
    }
}
