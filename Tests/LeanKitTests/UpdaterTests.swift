import CryptoKit
import Foundation
import Testing
@testable import LeanKit

@MainActor
@Suite struct UpdaterTests {
    @Test func staleListsOnlyChangedOrMissingFiles() {
        let m = UpdateManifest(commit: "c", binary: "b", files: [
            "addons/default/same.js": "1", "addons/default/changed.js": "2", "addons/optional/new.js": "3"])
        let local = ["addons/default/same.js": "1", "addons/default/changed.js": "old"]
        #expect(Updater.stale(m) { local[$0] } == ["addons/default/changed.js", "addons/optional/new.js"])
        #expect(Updater.stale(m) { m.files[$0] }.isEmpty)
    }

    @Test func onlyAddonScriptsAreWritable() {
        #expect(Updater.isSafe("addons/default/history.js"))
        #expect(Updater.isSafe("addons/optional/dark-mode_2.js"))
        for bad in ["../x.js", "addons/default/../../x.js", "addons/user/x.js", "addons/default/x.sh",
                    "addons/default/sub/x.js", "/etc/passwd", "addons/default/.x.js", "addons/default/x.js\n"] {
            #expect(!Updater.isSafe(bad), "\(bad)")
        }
    }

    @Test func assetNamesAreFlat() {
        #expect(Updater.asset("addons/default/history.js") == "addons__default__history.js")
    }

    @Test func hashIsHexSha256() {
        #expect(Updater.sha256(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func onlyManifestsSignedByTheKeyVerify() throws {
        let key = Curve25519.Signing.PrivateKey(), other = Curve25519.Signing.PrivateKey()
        let pub = key.publicKey.rawRepresentation.base64EncodedString()
        let data = Data(#"{"commit":"c","binary":"b","files":{}}"#.utf8)
        let sig = try key.signature(for: data)
        #expect(Updater.verify(data, signature: sig, key: pub))
        #expect(!Updater.verify(data + Data(" ".utf8), signature: sig, key: pub))
        #expect(!Updater.verify(data, signature: try other.signature(for: data), key: pub))
        #expect(!Updater.verify(data, signature: sig, key: ""))   // no key set: nothing verifies
    }

    @Test func manifestDecodes() throws {
        let json = #"{"commit":"abc","binary":"dead","files":{"addons/default/a.js":"beef"}}"#
        let m = try JSONDecoder().decode(UpdateManifest.self, from: Data(json.utf8))
        #expect(m == UpdateManifest(commit: "abc", binary: "dead", files: ["addons/default/a.js": "beef"]))
    }

    @Test func updatedFilesOnlyApplyToTheInstallTheyWereMadeFor() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "upd-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(Updater.overlay(in: dir, commit: "abc") == nil)   // no state yet
        try JSONEncoder().encode(Updater.State(base: "abc", commit: "new")).write(to: dir.appending(path: "state.json"))
        #expect(Updater.overlay(in: dir, commit: "abc") == dir)
        #expect(Updater.overlay(in: dir, commit: "other") == nil)  // reinstalled app
        #expect(Updater.overlay(in: dir, commit: "dev") == nil)    // local builds ignore updates
    }
}
