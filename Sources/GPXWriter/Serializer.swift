// Copyright © 2017-2026 Robert Horrion.

import Foundation

struct Serializer {
    func xml(_ gpx: GPX, prettyPrinted: Bool) throws -> String {
        try gpx.validate()
        var writer = XMLWriter(pretty: prettyPrinted)
        writer.write(gpx)
        return writer.output
    }
}

private struct XMLWriter {
    let pretty: Bool
    private(set) var output = ""
    private var depth = 0

    mutating func write(_ gpx: GPX) {
        output = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        let attributes = [
            XMLAttribute(name: "version", value: gpx.version.rawValue),
            XMLAttribute(name: "creator", value: gpx.creator),
            XMLAttribute(name: "xmlns", value: gpx.version.namespaceURI),
            XMLAttribute(name: "xmlns:xsi", value: "http://www.w3.org/2001/XMLSchema-instance"),
            XMLAttribute(name: "xsi:schemaLocation", value: gpx.version.schemaLocation),
        ]
        guard documentHasContent(gpx) else {
            empty("gpx", attributes)
            finish()
            return
        }
        open("gpx", attributes)
        switch gpx.version {
        case .v1_0:
            writeLegacyMetadata(gpx.metadata)
        case .v1_1:
            if metadataHasContent(gpx.metadata) {
                writeMetadata(gpx.metadata)
            }
        }
        for waypoint in gpx.waypoints {
            writePoint(waypoint, name: "wpt", version: gpx.version, courseAndSpeed: false)
        }
        for route in gpx.routes {
            writeRoute(route, version: gpx.version)
        }
        for track in gpx.tracks {
            writeTrack(track, version: gpx.version)
        }
        extensions(gpx.extensions, version: gpx.version)
        close("gpx")
        finish()
    }

    private mutating func writeLegacyMetadata(_ metadata: Metadata) {
        text("name", metadata.name)
        text("desc", metadata.description)
        if let author = metadata.author {
            if let name = author.name {
                text("author", name)
            } else if author.email == nil {
                text("author", "")
            }
            if let email = author.email {
                text("email", email.address)
            }
        }
        legacyLink(metadata.links)
        date("time", metadata.time)
        text("keywords", metadata.keywords)
        if let bounds = metadata.bounds {
            writeBounds(bounds)
        }
    }

    private mutating func writeMetadata(_ metadata: Metadata) {
        open("metadata")
        text("name", metadata.name)
        text("desc", metadata.description)
        if let author = metadata.author {
            writePerson(author)
        }
        if let copyright = metadata.copyright {
            writeCopyright(copyright)
        }
        links(metadata.links)
        date("time", metadata.time)
        text("keywords", metadata.keywords)
        if let bounds = metadata.bounds {
            writeBounds(bounds)
        }
        extensions(metadata.extensions, version: .v1_1)
        close("metadata")
    }

    private mutating func writePerson(_ person: Person) {
        let hasChild = person.name != nil || person.email != nil || person.link != nil
        guard hasChild else {
            empty("author")
            return
        }
        open("author")
        text("name", person.name)
        if let email = person.email {
            empty("email", [
                XMLAttribute(name: "id", value: email.id),
                XMLAttribute(name: "domain", value: email.domain),
            ])
        }
        if let link = person.link {
            links([link])
        }
        close("author")
    }

    private mutating func writeCopyright(_ copyright: Copyright) {
        let attributes = [XMLAttribute(name: "author", value: copyright.author)]
        if copyright.year == nil, copyright.license == nil {
            empty("copyright", attributes)
            return
        }
        open("copyright", attributes)
        if let year = copyright.year {
            text("year", XMLCodec.formatYear(year))
        }
        text("license", copyright.license)
        close("copyright")
    }

    private mutating func writeBounds(_ bounds: Bounds) {
        empty("bounds", [
            XMLAttribute(name: "minlat", value: XMLCodec.formatDecimal(bounds.minimumLatitude)),
            XMLAttribute(name: "minlon", value: XMLCodec.formatDecimal(bounds.minimumLongitude)),
            XMLAttribute(name: "maxlat", value: XMLCodec.formatDecimal(bounds.maximumLatitude)),
            XMLAttribute(name: "maxlon", value: XMLCodec.formatDecimal(bounds.maximumLongitude)),
        ])
    }

    private mutating func writeRoute(_ route: Route, version: GPX.Version) {
        guard routeHasContent(route) else {
            empty("rte")
            return
        }
        open("rte")
        text("name", route.name)
        text("cmt", route.comment)
        text("desc", route.description)
        text("src", route.source)
        if version == .v1_0 {
            legacyLink(route.links)
        } else {
            links(route.links)
        }
        integer("number", route.number)
        if version == .v1_1 {
            text("type", route.type)
        }
        extensions(route.extensions, version: version)
        for point in route.points {
            writePoint(point, name: "rtept", version: version, courseAndSpeed: false)
        }
        close("rte")
    }

    private mutating func writeTrack(_ track: Track, version: GPX.Version) {
        guard trackHasContent(track, version: version) else {
            empty("trk")
            return
        }
        open("trk")
        text("name", track.name)
        text("cmt", track.comment)
        text("desc", track.description)
        text("src", track.source)
        if version == .v1_0 {
            legacyLink(track.links)
        } else {
            links(track.links)
        }
        integer("number", track.number)
        if version == .v1_1 {
            text("type", track.type)
        }
        extensions(track.extensions, version: version)
        for segment in track.segments {
            writeSegment(segment, version: version)
        }
        close("trk")
    }

    private mutating func writeSegment(_ segment: TrackSegment, version: GPX.Version) {
        let hasExtensions = version == .v1_1 && segment.extensions?.elements.isEmpty == false
        guard !segment.points.isEmpty || hasExtensions else {
            empty("trkseg")
            return
        }
        open("trkseg")
        for point in segment.points {
            writePoint(point, name: "trkpt", version: version, courseAndSpeed: version == .v1_0)
        }
        if version == .v1_1 {
            extensions(segment.extensions, version: version)
        }
        close("trkseg")
    }

    private mutating func writePoint(
        _ point: Waypoint,
        name: String,
        version: GPX.Version,
        courseAndSpeed: Bool
    ) {
        let attributes = [
            XMLAttribute(name: "lat", value: XMLCodec.formatDecimal(point.latitude)),
            XMLAttribute(name: "lon", value: XMLCodec.formatDecimal(point.longitude)),
        ]
        guard pointHasContent(point, version: version, courseAndSpeed: courseAndSpeed) else {
            empty(name, attributes)
            return
        }
        open(name, attributes)
        decimal("ele", point.elevation)
        date("time", point.time)
        if courseAndSpeed {
            decimal("course", point.course)
            decimal("speed", point.speed)
        }
        decimal("magvar", point.magneticVariation)
        decimal("geoidheight", point.geoidHeight)
        text("name", point.name)
        text("cmt", point.comment)
        text("desc", point.description)
        text("src", point.source)
        if version == .v1_0 {
            legacyLink(point.links)
        } else {
            links(point.links)
        }
        text("sym", point.symbol)
        text("type", point.type)
        if let fix = point.fix {
            text("fix", fix.rawValue)
        }
        integer("sat", point.satelliteCount)
        decimal("hdop", point.horizontalDilution)
        decimal("vdop", point.verticalDilution)
        decimal("pdop", point.positionDilution)
        decimal("ageofdgpsdata", point.ageOfDGPSData)
        integer("dgpsid", point.dgpsStationID)
        extensions(point.extensions, version: version)
        close(name)
    }

    private mutating func links(_ links: [Link]) {
        for link in links {
            let attributes = [XMLAttribute(name: "href", value: link.href)]
            if link.text == nil, link.mimeType == nil {
                empty("link", attributes)
            } else {
                open("link", attributes)
                text("text", link.text)
                text("type", link.mimeType)
                close("link")
            }
        }
    }

    private mutating func legacyLink(_ links: [Link]) {
        guard let link = links.first else { return }
        text("url", link.href)
        text("urlname", link.text)
    }

    private mutating func extensions(_ extensions: Extensions?, version: GPX.Version) {
        guard let extensions, !extensions.elements.isEmpty else { return }
        if version == .v1_1 {
            open("extensions")
            for element in extensions.elements {
                writeRaw(element)
            }
            close("extensions")
        } else {
            for element in extensions.elements {
                writeRaw(element)
            }
        }
    }

    private mutating func writeRaw(_ element: XMLElement) {
        if element.children.isEmpty {
            empty(element.name, element.attributes)
            return
        }
        if element.children.count == 1, case .text(let text) = element.children[0] {
            writeIndent()
            output += "<\(element.name)\(attributeText(element.attributes))>\(XMLCodec.escapeText(text))</\(element.name)>"
            newline()
            return
        }
        open(element.name, element.attributes)
        for child in element.children {
            switch child {
            case .text(let text):
                writeIndent()
                output += XMLCodec.escapeText(text)
                newline()
            case .element(let child):
                writeRaw(child)
            }
        }
        close(element.name)
    }

    private func documentHasContent(_ gpx: GPX) -> Bool {
        if !gpx.waypoints.isEmpty || !gpx.routes.isEmpty || !gpx.tracks.isEmpty {
            return true
        }
        if gpx.extensions?.elements.isEmpty == false {
            return true
        }
        switch gpx.version {
        case .v1_0:
            return legacyMetadataHasContent(gpx.metadata)
        case .v1_1:
            return metadataHasContent(gpx.metadata)
        }
    }

    private func legacyMetadataHasContent(_ metadata: Metadata) -> Bool {
        metadata.name != nil || metadata.description != nil || metadata.author != nil || !metadata.links.isEmpty
            || metadata.time != nil || metadata.keywords != nil || metadata.bounds != nil
    }

    private func metadataHasContent(_ metadata: Metadata) -> Bool {
        legacyMetadataHasContent(metadata) || metadata.copyright != nil || metadata.extensions?.elements.isEmpty == false
    }

    private func routeHasContent(_ route: Route) -> Bool {
        route.name != nil || route.comment != nil || route.description != nil || route.source != nil
            || !route.links.isEmpty || route.number != nil || route.type != nil
            || route.extensions?.elements.isEmpty == false || !route.points.isEmpty
    }

    private func trackHasContent(_ track: Track, version: GPX.Version) -> Bool {
        if track.name != nil || track.comment != nil || track.description != nil || track.source != nil
            || !track.links.isEmpty || track.number != nil || track.type != nil
            || track.extensions?.elements.isEmpty == false
        {
            return true
        }
        return track.segments.contains { segment in
            !segment.points.isEmpty || (version == .v1_1 && segment.extensions?.elements.isEmpty == false)
        }
    }

    private func pointHasContent(_ point: Waypoint, version: GPX.Version, courseAndSpeed: Bool) -> Bool {
        if point.elevation != nil || point.time != nil || point.magneticVariation != nil || point.geoidHeight != nil {
            return true
        }
        if courseAndSpeed, point.course != nil || point.speed != nil {
            return true
        }
        if point.name != nil || point.comment != nil || point.description != nil || point.source != nil {
            return true
        }
        if !point.links.isEmpty || point.symbol != nil || point.type != nil || point.fix != nil || point.satelliteCount != nil {
            return true
        }
        if point.horizontalDilution != nil || point.verticalDilution != nil || point.positionDilution != nil {
            return true
        }
        if point.ageOfDGPSData != nil || point.dgpsStationID != nil {
            return true
        }
        return point.extensions?.elements.isEmpty == false
    }

    private mutating func text(_ name: String, _ value: String?) {
        guard let value else { return }
        writeIndent()
        output += "<\(name)>\(XMLCodec.escapeText(value))</\(name)>"
        newline()
    }

    private mutating func decimal(_ name: String, _ value: Double?) {
        guard let value else { return }
        text(name, XMLCodec.formatDecimal(value))
    }

    private mutating func integer(_ name: String, _ value: Int?) {
        guard let value else { return }
        text(name, XMLCodec.formatInteger(value))
    }

    private mutating func date(_ name: String, _ value: Date?) {
        guard let value else { return }
        text(name, XMLCodec.formatDate(value))
    }

    private mutating func open(_ name: String, _ attributes: [XMLAttribute] = []) {
        writeIndent()
        output += "<\(name)\(attributeText(attributes))>"
        newline()
        depth += 1
    }

    private mutating func close(_ name: String) {
        depth -= 1
        writeIndent()
        output += "</\(name)>"
        newline()
    }

    private mutating func empty(_ name: String, _ attributes: [XMLAttribute] = []) {
        writeIndent()
        output += "<\(name)\(attributeText(attributes))/>"
        newline()
    }

    private func attributeText(_ attributes: [XMLAttribute]) -> String {
        attributes.map { attribute in
            " \(attribute.name)=\"\(XMLCodec.escapeAttribute(attribute.value))\""
        }.joined()
    }

    private mutating func writeIndent() {
        guard pretty else { return }
        output += String(repeating: "  ", count: depth)
    }

    private mutating func newline() {
        guard pretty else { return }
        output += "\n"
    }

    private mutating func finish() {
        if !output.hasSuffix("\n") {
            output += "\n"
        }
    }
}
