import Foundation
import Testing

@testable import Todos

@Suite struct ImageEmbedTests {
    @Test func isNamedAfterWhenItWasPastedAsObsidianNamesIt() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        let parts = DateComponents(year: 2026, month: 11, day: 6, hour: 9, minute: 5, second: 7)
        let date = calendar.date(from: parts) ?? .now
        #expect(ImageEmbed.name(at: date, calendar: calendar) == "Pasted image 20261106090507.png")
    }

    @Test func embedsAsAWikiLink() {
        #expect(ImageEmbed.embed("Pasted image 1.png") == "![[Pasted image 1.png]]")
    }

    @Test func findsEachImageOnceAndPassesOverNotes() {
        let text = "Look ![[a.png]] and ![[b.JPG|300]] ![[a.png]] ![[Weekly sync]] [[c.png]]"
        #expect(ImageEmbed.names(in: text) == ["a.png", "b.JPG"])
    }

    @Test func splitsTextAroundImagesKeepingEachAsWritten() {
        #expect(ImageEmbed.segments(of: "a ![[x.png|300]] b ![[Note]]![[y.jpg]]") == [
            .text("a "), .image(name: "x.png", raw: "![[x.png|300]]"), .text(" b ![[Note]]"),
            .image(name: "y.jpg", raw: "![[y.jpg]]")
        ])
        #expect(ImageEmbed.segments(of: "") == [])
    }

    @Test func stripsImagesButKeepsTheRest() {
        #expect(ImageEmbed.stripped("Fix ![[a.png]] this #bug") == "Fix this #bug")
        #expect(ImageEmbed.stripped("![[a.png]]") == "")
        #expect(ImageEmbed.stripped("See ![[Weekly sync]]") == "See ![[Weekly sync]]")
        #expect(ImageEmbed.stripped("one ![[a.png]]\ntwo") == "one\ntwo")
    }
}
