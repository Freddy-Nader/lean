// Ed25519 key for update manifests. Usage:
//   swift scripts/update-key.swift keygen          prints a new key pair (once per project)
//   swift scripts/update-key.swift sign <file>     writes <file minus .json>.sig, key in $LEAN_UPDATE_KEY
// The public key goes in Updater.publicKey; the private key in the LEAN_UPDATE_KEY repo secret.
import CryptoKit
import Foundation

func fail(_ s: String) -> Never { FileHandle.standardError.write(Data((s + "\n").utf8)); exit(1) }

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "keygen":
    let k = Curve25519.Signing.PrivateKey()
    print("public  (Updater.publicKey):        \(k.publicKey.rawRepresentation.base64EncodedString())")
    print("private (LEAN_UPDATE_KEY secret):   \(k.rawRepresentation.base64EncodedString())")
case "sign" where args.count == 2:
    guard let b64 = ProcessInfo.processInfo.environment["LEAN_UPDATE_KEY"], let raw = Data(base64Encoded: b64),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else { fail("LEAN_UPDATE_KEY is missing or invalid") }
    let file = URL(fileURLWithPath: args.last!)
    guard let data = try? Data(contentsOf: file) else { fail("cannot read \(file.path)") }
    let sig = try key.signature(for: data)
    try sig.write(to: file.deletingPathExtension().appendingPathExtension("sig"))
    print("signed \(file.lastPathComponent)")
default:
    fail("usage: update-key.swift keygen | sign <manifest.json>")
}
