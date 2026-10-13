import Foundation
import Testing
@testable import LeanKit

@MainActor
@Suite struct AddressTests {
    @Test func fullURL() { #expect(Address.resolve("https://a.com/x")?.absoluteString == "https://a.com/x") }
    @Test func bareDomain() { #expect(Address.resolve("wikipedia.org")?.absoluteString == "https://wikipedia.org") }
    @Test func domainWithPath() { #expect(Address.resolve("github.com/apple")?.absoluteString == "https://github.com/apple") }
    @Test func localhost() { #expect(Address.resolve("localhost:3000")?.absoluteString == "http://localhost:3000") }
    @Test func ip() { #expect(Address.resolve("192.168.1.1")?.absoluteString == "http://192.168.1.1") }
    @Test func searchWords() { #expect(Address.resolve("swift browser")?.absoluteString == "https://www.google.com/search?q=swift%20browser") }
    @Test func searchSymbols() { #expect(Address.resolve("a&b=c")?.absoluteString == "https://www.google.com/search?q=a%26b%3Dc") }
    @Test func versionIsNotDomain() { #expect(Address.resolve("v1.2")?.host() == "www.google.com") }
    @Test func displayHost() {
        func d(_ s: String?) -> String { Address.displayHost(s.flatMap(URL.init(string:))) }
        #expect(d("https://www.inkandswitch.com/essay/x?y") == "inkandswitch.com")
        #expect(d("https://news.ycombinator.com/item?id=1") == "news.ycombinator.com")
        #expect(d("lean://settings") == "lean://settings")
        #expect(d("http://localhost:3000/a") == "localhost")
        #expect(d("file:///tmp/a.html") == "a.html")
        #expect(d(nil) == "")
    }
    @Test func empty() { #expect(Address.resolve("   ") == nil) }
}

@MainActor
@Suite struct DownloadsTests {
    @Test func uniqueNames() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appending(path: "a.pdf")
        #expect(Downloads.unique(f) == f)
        FileManager.default.createFile(atPath: f.path, contents: Data())
        #expect(Downloads.unique(f).lastPathComponent == "a 2.pdf")
    }
}
