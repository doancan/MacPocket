import CoreAudio
import Foundation

/// Core Audio requires the very same block and queue when removing a listener.
@MainActor
final class AudioPropertyObservers {
    private var entries: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    func add(_ selector: AudioObjectPropertySelector, object: AudioObjectID = AudioObjectID(kAudioObjectSystemObject),
             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, callback: @escaping AudioObjectPropertyListenerBlock) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                                mElement: kAudioObjectPropertyElementMain)
        if AudioObjectAddPropertyListenerBlock(object, &address, .main, callback) == noErr {
            entries.append((object, address, callback))
        }
    }

    #if DEBUG
    var count: Int { entries.count }
    #endif

    func removeAll() {
        for (object, address, callback) in entries {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, callback)
        }
        entries = []
    }
}
