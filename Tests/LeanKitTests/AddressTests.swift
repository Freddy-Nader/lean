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
    @Test func empty() { #expect(Address.resolve("   ") == nil) }
}
