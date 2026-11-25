// Copyright © 2017-2026 Robert Horrion.

import XCTest
@testable import GPXWriter

final class GPXWriterTests: XCTestCase {
    func testWritesGPX11Document() throws {
        var gpx = GPX(creator: "GPXWriter")
        gpx.metadata.name = "Sample"
        gpx.metadata.description = "A & B <sample>"
        gpx.metadata.author = Person(
            name: "Robert",
            email: Email(id: "robert", domain: "example.com"),
            link: Link(href: "https://example.com/robert", text: "Robert")
        )
        gpx.metadata.copyright = Copyright(author: "Robert Horrion", year: 2017, license: "https://example.com/license")
        gpx.metadata.links = [Link(href: "https://example.com/file", text: "File", mimeType: "text/html")]
        gpx.metadata.time = utc(2017, 9, 6, 12, 30, 0)
        gpx.metadata.keywords = "gps, test"
        gpx.metadata.bounds = Bounds(minimumLatitude: 12, minimumLongitude: -80, maximumLatitude: 36, maximumLongitude: -58)
        gpx.waypoints = [
            Waypoint(
                latitude: 35.0185442384,
                longitude: -79.4639757277,
                elevation: 12.33,
                time: utc(2017, 9, 6, 12, 31, 0),
                magneticVariation: 7.5,
                geoidHeight: -31.2,
                name: "Start",
                comment: "Gate",
                description: "North gate",
                source: "GPS",
                links: [Link(href: "https://example.com/start")],
                symbol: "Flag",
                type: "Waypoint",
                fix: .threeDimensional,
                satelliteCount: 8,
                horizontalDilution: 1.1,
                verticalDilution: 1.8,
                positionDilution: 2.1,
                ageOfDGPSData: 3.5,
                dgpsStationID: 42
            )
        ]

        let xml = try gpx.xml()
        XCTAssertEqual(
            xml,
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx version="1.1" creator="GPXWriter" xmlns="http://www.topografix.com/GPX/1/1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
              <metadata>
                <name>Sample</name>
                <desc>A &amp; B &lt;sample&gt;</desc>
                <author>
                  <name>Robert</name>
                  <email id="robert" domain="example.com"/>
                  <link href="https://example.com/robert">
                    <text>Robert</text>
                  </link>
                </author>
                <copyright author="Robert Horrion">
                  <year>2017</year>
                  <license>https://example.com/license</license>
                </copyright>
                <link href="https://example.com/file">
                  <text>File</text>
                  <type>text/html</type>
                </link>
                <time>2017-09-06T12:30:00Z</time>
                <keywords>gps, test</keywords>
                <bounds minlat="12.0" minlon="-80.0" maxlat="36.0" maxlon="-58.0"/>
              </metadata>
              <wpt lat="35.0185442384" lon="-79.4639757277">
                <ele>12.33</ele>
                <time>2017-09-06T12:31:00Z</time>
                <magvar>7.5</magvar>
                <geoidheight>-31.2</geoidheight>
                <name>Start</name>
                <cmt>Gate</cmt>
                <desc>North gate</desc>
                <src>GPS</src>
                <link href="https://example.com/start"/>
                <sym>Flag</sym>
                <type>Waypoint</type>
                <fix>3d</fix>
                <sat>8</sat>
                <hdop>1.1</hdop>
                <vdop>1.8</vdop>
                <pdop>2.1</pdop>
                <ageofdgpsdata>3.5</ageofdgpsdata>
                <dgpsid>42</dgpsid>
              </wpt>
            </gpx>

            """
        )
        XCTAssertEqual(try GPX(xml: xml), gpx)
    }

    func testWritesGPX10Document() throws {
        var gpx = GPX(version: .v1_0, creator: "GPXWriter")
        gpx.metadata.name = "Legacy"
        gpx.metadata.description = "Old file"
        gpx.metadata.author = Person(name: "Robert", email: try Email(address: "robert@example.com"))
        gpx.metadata.links = [Link(href: "https://example.com/legacy", text: "Legacy")]
        gpx.metadata.time = utc(2002, 10, 1, 0, 0, 0)
        gpx.metadata.keywords = "legacy"
        gpx.metadata.bounds = Bounds(minimumLatitude: -90, minimumLongitude: -180, maximumLatitude: 90, maximumLongitude: 180)
        gpx.waypoints = [Waypoint(latitude: 1, longitude: 2, name: "Pin", links: [Link(href: "https://example.com/pin", text: "Pin")])]
        gpx.routes = [Route(name: "Home", number: 3, points: [Waypoint(latitude: 3, longitude: 4)])]
        gpx.tracks = [
            Track(
                name: "Morning",
                number: 1,
                segments: [
                    TrackSegment(points: [
                        Waypoint(
                            latitude: 35.0185442384,
                            longitude: -79.4639757277,
                            elevation: 12.33,
                            time: utc(2017, 9, 6, 12, 31, 0),
                            course: 90,
                            speed: 166.53,
                            fix: .twoDimensional,
                            satelliteCount: 4
                        ),
                        Waypoint(latitude: 12.88888, longitude: -58.999999, speed: 188.01, name: "Testy", satelliteCount: 8)
                    ])
                ]
            )
        ]

        let xml = try gpx.xml()
        XCTAssertFalse(xml.contains("<metadata"))
        XCTAssertFalse(xml.contains("<extensions"))
        XCTAssertFalse(xml.contains("<link"))
        let course = try XCTUnwrap(xml.range(of: "<course>90.0</course>"))
        let speed = try XCTUnwrap(xml.range(of: "<speed>166.53</speed>"))
        let magvarSlot = xml.range(of: "<magvar>")
        XCTAssertLessThan(course.lowerBound, speed.lowerBound)
        XCTAssertNil(magvarSlot)
        XCTAssertEqual(try GPX(xml: xml), gpx)

        let second = try XCTUnwrap(gpx.tracks.first?.segments.first?.points.last)
        XCTAssertEqual(second.name, "Testy")
        XCTAssertEqual(second.speed, 188.01)
        XCTAssertNil(second.course)
    }

    func testRoundTripsEveryGPX11Field() throws {
        let extensionElement = XMLElement(
            name: "gpxtpx:TrackPointExtension",
            attributes: [XMLAttribute(name: "xmlns:gpxtpx", value: "http://www.garmin.com/xmlschemas/TrackPointExtension/v1")],
            children: [.element(XMLElement(name: "gpxtpx:hr", text: "140"))]
        )
        var gpx = GPX(creator: "Field Test")
        gpx.metadata = Metadata(
            name: "All",
            description: "Fields",
            author: Person(name: "Ada", email: Email(id: "ada", domain: "example.com"), link: Link(href: "https://example.com/ada")),
            copyright: Copyright(author: "Ada", year: 999, license: "https://example.com/license"),
            links: [Link(href: "https://example.com/a", text: "A", mimeType: "text/plain"), Link(href: "https://example.com/b")],
            time: utc(2024, 1, 2, 3, 4, 5),
            keywords: "one, two",
            bounds: Bounds(minimumLatitude: -1.5, minimumLongitude: -2.5, maximumLatitude: 3.5, maximumLongitude: 4.5),
            extensions: Extensions(elements: [XMLElement(name: "ext:meta", attributes: [XMLAttribute(name: "xmlns:ext", value: "urn:ext")], text: "meta")])
        )
        gpx.waypoints = [Waypoint(latitude: 10, longitude: 20, name: "W")]
        gpx.routes = [
            Route(
                name: "R",
                comment: "rc",
                description: "rd",
                source: "rs",
                links: [Link(href: "https://example.com/r", text: "Route")],
                number: 7,
                type: "road",
                extensions: Extensions(elements: [XMLElement(name: "ext:route", attributes: [XMLAttribute(name: "xmlns:ext", value: "urn:ext")], text: "r")]),
                points: [Waypoint(latitude: 11, longitude: 21, comment: "turn")]
            )
        ]
        gpx.tracks = [
            Track(
                name: "T",
                comment: "tc",
                description: "td",
                source: "ts",
                links: [Link(href: "https://example.com/t")],
                number: 0,
                type: "hike",
                extensions: Extensions(elements: [XMLElement(name: "ext:track", attributes: [XMLAttribute(name: "xmlns:ext", value: "urn:ext")], text: "t")]),
                segments: [
                    TrackSegment(points: [
                        Waypoint(latitude: 12, longitude: 22, extensions: Extensions(elements: [extensionElement]))
                    ], extensions: Extensions(elements: [XMLElement(name: "ext:segment", attributes: [XMLAttribute(name: "xmlns:ext", value: "urn:ext")], text: "s")])),
                    TrackSegment()
                ]
            )
        ]
        gpx.extensions = Extensions(elements: [XMLElement(name: "ext:root", attributes: [XMLAttribute(name: "xmlns:ext", value: "urn:ext")], text: "root")])

        let parsed = try GPX(xml: try gpx.xml())
        XCTAssertEqual(parsed, gpx)
        XCTAssertEqual(parsed.metadata.copyright?.year, 999)
        XCTAssertEqual(parsed.tracks.first?.segments.first?.points.first?.extensions?.elements.first?.children, [.element(XMLElement(name: "gpxtpx:hr", text: "140"))])
    }

    func testPreservesExtensionNamespaceDeclaredOnTheRoot() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx xmlns="http://www.topografix.com/GPX/1/1" xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1" version="1.1" creator="Garmin">
          <trk>
            <trkseg>
              <trkpt lat="1.0" lon="2.0">
                <extensions>
                  <gpxtpx:TrackPointExtension>
                    <gpxtpx:hr>140</gpxtpx:hr>
                  </gpxtpx:TrackPointExtension>
                </extensions>
              </trkpt>
            </trkseg>
          </trk>
        </gpx>
        """
        let parsed = try GPX(xml: xml)
        let element = try XCTUnwrap(parsed.tracks.first?.segments.first?.points.first?.extensions?.elements.first)
        XCTAssertEqual(element.name, "gpxtpx:TrackPointExtension")
        XCTAssertEqual(element.attributes.first { $0.name == "xmlns:gpxtpx" }?.value, "http://www.garmin.com/xmlschemas/TrackPointExtension/v1")
        XCTAssertEqual(element.children, [.element(XMLElement(name: "gpxtpx:hr", text: "140"))])
        XCTAssertEqual(try GPX(xml: try parsed.xml()), parsed)
    }

    func testReadsGPX10ForeignElementsAndCourse() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.0" creator="Device" xmlns="http://www.topografix.com/GPX/1/0">
          <name>Day</name>
          <author>Robert</author>
          <email>robert@example.com</email>
          <url>https://example.com</url>
          <urlname>Example</urlname>
          <wpt lat="45.0" lon="180.0">
            <name>Edge</name>
            <url>https://example.com/w</url>
            <urlname>Edge</urlname>
          </wpt>
          <trk>
            <trkseg>
              <trkpt lat="-90.0" lon="-180.0">
                <ele>1.0</ele>
                <time>2002-10-01T00:00:00Z</time>
                <course>360.0</course>
                <speed>1.25</speed>
                <magvar>0.0</magvar>
                <t:note xmlns:t="urn:test">marked</t:note>
              </trkpt>
            </trkseg>
          </trk>
        </gpx>
        """
        let parsed = try GPX(xml: xml)
        XCTAssertEqual(parsed.version, .v1_0)
        XCTAssertEqual(parsed.metadata.author?.name, "Robert")
        XCTAssertEqual(parsed.metadata.author?.email?.address, "robert@example.com")
        XCTAssertEqual(parsed.metadata.links, [Link(href: "https://example.com", text: "Example")])
        XCTAssertEqual(parsed.waypoints.first?.longitude, 180)
        let point = try XCTUnwrap(parsed.tracks.first?.segments.first?.points.first)
        XCTAssertEqual(point.course, 360)
        XCTAssertEqual(point.speed, 1.25)
        XCTAssertEqual(point.magneticVariation, 0)
        XCTAssertEqual(point.extensions?.elements.first?.name, "t:note")
        XCTAssertEqual(point.extensions?.elements.first?.children, [.text("marked")])
        let rewritten = try parsed.xml()
        XCTAssertFalse(rewritten.contains("<extensions"))
        XCTAssertTrue(rewritten.contains("<t:note"))
        XCTAssertEqual(try GPX(xml: rewritten), parsed)
    }

    func testParsesDateTimeForms() throws {
        let xml = """
        <gpx version="1.1" creator="Dates">
          <metadata>
            <time>2020-01-02T03:04:05.5Z</time>
          </metadata>
          <wpt lat="1" lon="2"><time>2020-01-02T05:04:05.123+02:00</time></wpt>
          <wpt lat="3" lon="4"><time>2020-01-02T01:04:05.123-02:00</time></wpt>
        </gpx>
        """
        let parsed = try GPX(xml: xml)
        XCTAssertEqual(parsed.metadata.time, utc(2020, 1, 2, 3, 4, 5, nanoseconds: 500_000_000))
        XCTAssertEqual(parsed.waypoints[0].time, utc(2020, 1, 2, 3, 4, 5, nanoseconds: 123_000_000))
        XCTAssertEqual(parsed.waypoints[1].time, utc(2020, 1, 2, 3, 4, 5, nanoseconds: 123_000_000))
        let written = try parsed.xml()
        XCTAssertTrue(written.contains("<time>2020-01-02T03:04:05.5Z</time>"))
        XCTAssertTrue(written.contains("<time>2020-01-02T03:04:05.123Z</time>"))
    }

    func testIgnoresCommentsAndReadsCDATA() throws {
        let xml = """
        <!-- comment -->
        <gpx version="1.1" creator="CDATA">
          <wpt lat="1" lon="2"><desc><![CDATA[A & B <C>]]></desc></wpt>
        </gpx>
        """
        let parsed = try GPX(xml: xml)
        XCTAssertEqual(parsed.waypoints.first?.description, "A & B <C>")
        XCTAssertTrue(try parsed.xml().contains("<desc>A &amp; B &lt;C&gt;</desc>"))
    }

    func testReadsAndWritesAFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gpxwriter-\(UUID().uuidString).gpx")
        let gpx = GPX(creator: "File", waypoints: [Waypoint(latitude: -33.5, longitude: 151.25, name: "Harbor")])
        try gpx.write(to: url)
        let read = try GPX(contentsOf: url)
        XCTAssertEqual(read, gpx)
        try? FileManager.default.removeItem(at: url)
    }

    func testWritesCompactXML() throws {
        let gpx = GPX(creator: "Compact", waypoints: [Waypoint(latitude: 1, longitude: 2, name: "A")])
        let xml = try gpx.xml(prettyPrinted: false)
        XCTAssertEqual(
            xml,
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx version="1.1" creator="Compact" xmlns="http://www.topografix.com/GPX/1/1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd"><wpt lat="1.0" lon="2.0"><name>A</name></wpt></gpx>

            """
        )
    }

    func testRejectsDocumentsThatDoNotMatchTheVersion() {
        XCTAssertEqual(reason(of: try GPX(xml: "<gpx creator=\"A\"/>")), .missingAttribute(element: "gpx", name: "version"))
        XCTAssertEqual(reason(of: try GPX(xml: "<gpx version=\"2.0\" creator=\"A\"/>")), .unsupportedVersion("2.0"))
        XCTAssertEqual(reason(of: try GPX(xml: "<gpx version=\"1.1\"><wpt lat=\"1\" lon=\"2\"/></gpx>")), .missingAttribute(element: "gpx", name: "creator"))
        XCTAssertEqual(reason(of: try GPX(xml: "<gpx version=\"1.1\" creator=\"A\"><wpt lon=\"2\"/></gpx>")), .missingAttribute(element: "wpt", name: "lat"))
        XCTAssertEqual(
            reason(of: try GPX(xml: "<gpx version=\"1.1\" creator=\"A\"><wpt lat=\"1\" lon=\"2\"><name>A</name><name>B</name></wpt></gpx>")),
            .duplicateElement("name", parent: "wpt")
        )
        XCTAssertEqual(
            reason(of: try GPX(xml: "<gpx version=\"1.1\" creator=\"A\"><wpt lat=\"1\" lon=\"2\"><fix>4d</fix></wpt></gpx>")),
            .invalidValue(element: "fix", value: "4d", expected: "none, 2d, 3d, dgps, or pps")
        )
        XCTAssertEqual(
            reason(of: try GPX(xml: "<gpx version=\"1.1\" creator=\"A\"><wpt lat=\"1\" lon=\"180\"/></gpx>")),
            .invalidValue(element: "lon", value: "180", expected: "a longitude from -180 up to, but not including, 180")
        )
        XCTAssertEqual(
            reason(of: try GPX(xml: "<gpx version=\"1.0\" creator=\"A\"><wpt lat=\"1\" lon=\"2\"><magvar>360.1</magvar></wpt></gpx>")),
            .invalidValue(element: "magvar", value: "360.1", expected: "degrees from 0 through 360")
        )
        XCTAssertEqual(
            reason(of: try GPX(xml: "<gpx version=\"1.1\" creator=\"A\"><wpt lat=\"1\" lon=\"2\"><magvar>360</magvar></wpt></gpx>")),
            .invalidValue(element: "magvar", value: "360", expected: "degrees from 0 up to, but not including, 360")
        )
        XCTAssertEqual(
            reason(of: try GPX(xml: "<gpx version=\"1.1\" creator=\"A\"><wpt lat=\"1\" lon=\"2\"><dgpsid>1024</dgpsid></wpt></gpx>")),
            .invalidValue(element: "dgpsid", value: "1024", expected: "an integer from 0 through 1023")
        )
        XCTAssertEqual(
            reason(of: try GPX(xml: "<gpx version=\"1.1\" creator=\"A\"><trk><trkseg><trkpt lat=\"1\" lon=\"2\"><speed>1</speed></trkpt></trkseg></trk></gpx>")),
            .unexpectedElement("speed", parent: "trkpt")
        )
        XCTAssertEqual(
            reason(of: try GPX(xml: "<gpx version=\"1.0\" creator=\"A\"><wpt lat=\"1\" lon=\"2\"><speed>1</speed></wpt></gpx>")),
            .unexpectedElement("speed", parent: "wpt")
        )
        XCTAssertEqual(
            reason(of: try GPX(xml: "<gpx version=\"1.0\" creator=\"A\"><urlname>Only</urlname></gpx>")),
            .invalidValue(element: "urlname", value: "Only", expected: "a url on the same element")
        )
        XCTAssertNil(try? GPX(xml: "<not-gpx/>"))
    }

    func testRejectsValuesTheChosenVersionCannotRepresent() throws {
        var modern = GPX(version: .v1_0, creator: "Old", metadata: Metadata(copyright: Copyright(author: "Robert")))
        XCTAssertEqual(reason(of: try modern.xml()), .unsupportedInVersion(.v1_0, detail: "Copyright"))

        modern.metadata.copyright = nil
        modern.metadata.links = [Link(href: "https://example.com/a"), Link(href: "https://example.com/b")]
        XCTAssertEqual(reason(of: try modern.xml()), .unsupportedInVersion(.v1_0, detail: "More than one link on metadata"))

        var current = GPX(
            creator: "New",
            tracks: [Track(segments: [TrackSegment(points: [Waypoint(latitude: 1, longitude: 2, speed: 3)])])]
        )
        XCTAssertEqual(reason(of: try current.xml()), .unsupportedInVersion(.v1_1, detail: "A course or speed"))

        current.tracks = []
        current.waypoints = [Waypoint(latitude: 1, longitude: 180)]
        XCTAssertEqual(
            reason(of: try current.xml()),
            .invalidValue(element: "lon", value: "180.0", expected: "a longitude from -180 up to, but not including, 180")
        )

        let legacy = GPX(version: .v1_0, creator: "Old", metadata: Metadata(author: Person(email: Email(id: "rob1", domain: "example.com"))))
        XCTAssertEqual(
            reason(of: try legacy.xml()),
            .invalidValue(element: "email", value: "rob1@example.com", expected: "a GPX 1.0 address of letters and underscores, such as name@example.com")
        )
    }

    private func utc(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        _ second: Int,
        nanoseconds: Int = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.nanosecond = nanoseconds
        return calendar.date(from: components)!
    }

    private func reason<T>(of body: @autoclosure () throws -> T) -> GPXError.Reason? {
        do {
            _ = try body()
            return nil
        } catch let error as GPXError {
            return error.reason
        } catch {
            return nil
        }
    }
}
