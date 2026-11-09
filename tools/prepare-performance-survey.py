#!/usr/bin/env python3
"""Instrument only an isolated checkout; original product sources are never written."""
import pathlib, re, shutil, subprocess, sys

original = pathlib.Path(sys.argv[1]).resolve()
checkout = pathlib.Path(sys.argv[2]).resolve()
if checkout == original or not (checkout / '.git').is_file():
    raise SystemExit('A separate git worktree is required')
counter = '''import Foundation
enum PerformanceSurveyCounters {
    private static let state = State()
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var counts: [String: Int] = [:]
    }
    static func record(_ name: String) { state.lock.withLock { state.counts[name, default: 0] += 1 } }
    static func reset() { state.lock.withLock { state.counts = [:] } }
    static func snapshot() -> [String: Int] { state.lock.withLock { state.counts } }
}
'''
(checkout / 'Sources/MacPocketApp/PerformanceSurveyCounters.swift').write_text(counter)
mapping = {}
for name in ['PocketSettingsView.swift', 'ToolsHubView.swift', 'PocketRootView.swift', 'OverviewView.swift']:
    path = checkout / 'Sources/MacPocketApp' / name
    pristine = subprocess.check_output(['git','-C',str(checkout),'show',f'HEAD:Sources/MacPocketApp/{name}'],text=True)
    lines = pristine.splitlines(keepends=True)
    current = name
    output = []
    for number, line in enumerate(lines, 1):
        match = re.search(r'\bstruct\s+(\w+)', line)
        if match:
            current = match.group(1)
        output.append(line)
        if re.search(r'\bvar body: some View\s*\{\s*$', line):
            label = f'{current}:{number}'
            output.append(f'        let _ = PerformanceSurveyCounters.record("{label}")\n')
            mapping[label] = name
    path.write_text(''.join(output))
shutil.copyfile(original / 'tools/PerformanceSurveyTests.swift', checkout / 'Tests/MacPocketAppTests/PerformanceSurveyTests.swift')
manifest = []
pristine_manifest = subprocess.check_output(['git','-C',str(checkout),'show','HEAD:Package.swift'],text=True)
for line in pristine_manifest.splitlines():
    if '.testTarget(' in line:
        if 'name: "MacPocketAppTests"' not in line:
            continue
        line = line.rstrip().removesuffix('),') + ', sources: ["PerformanceSurveyTests.swift"]),'
    manifest.append(line)
(checkout / 'Package.swift').write_text('\n'.join(manifest) + '\n')
import json
(checkout.parent / 'body-map.json').write_text(json.dumps(mapping, indent=2))
