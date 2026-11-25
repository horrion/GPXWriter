// Copyright © 2017-2026 Robert Horrion.

import Foundation

/// A GPX document: the GPS Exchange Format published by TopoGrafix.
///
/// GPX 1.0 (2002) and GPX 1.1 (2004) are the only published versions. The model
/// covers every element and attribute in both schemas. Fields that exist in only
/// one version are rejected when writing the other version.
public struct GPX: Equatable, Sendable {
    /// Published GPX schema versions.
    public enum Version: String, Equatable, Sendable, CaseIterable {
        case v1_0 = "1.0"
        case v1_1 = "1.1"

        /// Target namespace URI for this version.
        public var namespaceURI: String {
            switch self {
            case .v1_0: "http://www.topografix.com/GPX/1/0"
            case .v1_1: "http://www.topografix.com/GPX/1/1"
            }
        }

        /// Canonical schema document URL.
        public var schemaURL: String {
            namespaceURI + "/gpx.xsd"
        }

        /// Value of `xsi:schemaLocation` for this version.
        public var schemaLocation: String {
            "\(namespaceURI) \(schemaURL)"
        }
    }

    /// `version` attribute. GPX 1.1 is the current published version.
    public var version: Version
    /// `creator` attribute. Name or URL of the software that created the document.
    public var creator: String
    /// File-level metadata. In GPX 1.0 these fields are direct children of `gpx`. In GPX 1.1 they are wrapped in `metadata`.
    public var metadata: Metadata
    /// Waypoints, in document order.
    public var waypoints: [Waypoint]
    /// Routes, in document order.
    public var routes: [Route]
    /// Tracks, in document order.
    public var tracks: [Track]
    /// Document-level extension elements. In GPX 1.1 they are written inside `extensions`. In GPX 1.0 they are written as foreign-namespace elements after the last track.
    public var extensions: Extensions?

    public init(
        version: Version = .v1_1,
        creator: String,
        metadata: Metadata = Metadata(),
        waypoints: [Waypoint] = [],
        routes: [Route] = [],
        tracks: [Track] = [],
        extensions: Extensions? = nil
    ) {
        self.version = version
        self.creator = creator
        self.metadata = metadata
        self.waypoints = waypoints
        self.routes = routes
        self.tracks = tracks
        self.extensions = extensions
    }

    /// Parses a GPX document from XML bytes.
    public init(data: Data) throws {
        self = try DocumentParser().parse(data)
    }

    /// Parses a GPX document from an XML string.
    public init(xml: String) throws {
        guard let data = xml.data(using: .utf8) else {
            throw GPXError(reason: .malformedXML("The XML string is not valid UTF-8."))
        }
        try self.init(data: data)
    }

    /// Reads a GPX file from a URL.
    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url))
    }

    /// Serializes this document to GPX XML.
    public func xml(prettyPrinted: Bool = true) throws -> String {
        try Serializer().xml(self, prettyPrinted: prettyPrinted)
    }

    /// Serializes this document to UTF-8 GPX XML.
    public func data(prettyPrinted: Bool = true) throws -> Data {
        Data(try xml(prettyPrinted: prettyPrinted).utf8)
    }

    /// Writes this document to a URL as UTF-8 GPX XML.
    public func write(to url: URL, prettyPrinted: Bool = true) throws {
        try data(prettyPrinted: prettyPrinted).write(to: url, options: .atomic)
    }

    func validate() throws {
        try SchemaRules.checkText(creator, element: "creator")
        try metadata.validate(version: version)
        try SchemaRules.checkExtensions(extensions, version: version, context: "gpx")
        for waypoint in waypoints {
            try waypoint.validate(version: version, role: .waypoint)
        }
        for route in routes {
            try route.validate(version: version)
        }
        for track in tracks {
            try track.validate(version: version)
        }
    }
}

/// File metadata. Field availability depends on `GPX.Version`.
public struct Metadata: Equatable, Sendable {
    /// `name`.
    public var name: String?
    /// `desc`.
    public var description: String?
    /// GPX 1.0 `author` and `email`, or the GPX 1.1 `author` person.
    public var author: Person?
    /// GPX 1.1 `copyright`.
    public var copyright: Copyright?
    /// GPX 1.0 `url` and `urlname`, or GPX 1.1 `link` elements.
    public var links: [Link]
    /// `time`. Creation time of the file.
    public var time: Date?
    /// `keywords`.
    public var keywords: String?
    /// `bounds`.
    public var bounds: Bounds?
    /// GPX 1.1 metadata `extensions`.
    public var extensions: Extensions?

    public init(
        name: String? = nil,
        description: String? = nil,
        author: Person? = nil,
        copyright: Copyright? = nil,
        links: [Link] = [],
        time: Date? = nil,
        keywords: String? = nil,
        bounds: Bounds? = nil,
        extensions: Extensions? = nil
    ) {
        self.name = name
        self.description = description
        self.author = author
        self.copyright = copyright
        self.links = links
        self.time = time
        self.keywords = keywords
        self.bounds = bounds
        self.extensions = extensions
    }

    func validate(version: GPX.Version) throws {
        try SchemaRules.checkText(name, element: "name")
        try SchemaRules.checkText(description, element: "desc")
        try SchemaRules.checkText(keywords, element: "keywords")
        try author?.validate(version: version)
        try SchemaRules.checkLinks(links, version: version, context: "metadata")
        if let bounds {
            try bounds.validate(version: version)
        }
        switch version {
        case .v1_0:
            if copyright != nil {
                throw GPXError(reason: .unsupportedInVersion(.v1_0, detail: "Copyright"))
            }
            if extensions != nil {
                throw GPXError(reason: .unsupportedInVersion(.v1_0, detail: "Metadata extensions"))
            }
        case .v1_1:
            try copyright?.validate()
            try SchemaRules.checkExtensions(extensions, version: version, context: "metadata")
        }
    }
}

/// A person or organization. GPX 1.0 stores the name and email as separate file-level strings. GPX 1.1 uses `personType`.
public struct Person: Equatable, Sendable {
    /// `name`, or the GPX 1.0 `author` string.
    public var name: String?
    /// GPX 1.0 `email`, or GPX 1.1 `email` (`id` and `domain`).
    public var email: Email?
    /// GPX 1.1 `link`.
    public var link: Link?

    public init(name: String? = nil, email: Email? = nil, link: Link? = nil) {
        self.name = name
        self.email = email
        self.link = link
    }

    func validate(version: GPX.Version) throws {
        try SchemaRules.checkText(name, element: "author")
        try email?.validate(version: version)
        if let link {
            switch version {
            case .v1_0:
                throw GPXError(reason: .unsupportedInVersion(.v1_0, detail: "An author link"))
            case .v1_1:
                try link.validate(version: version)
            }
        }
    }
}

/// An email address. GPX 1.1 stores it as `id` and `domain` attributes. GPX 1.0 stores `id@domain` and restricts both halves to letters and underscores.
public struct Email: Equatable, Sendable {
    /// The `id` half, before `@`.
    public var id: String
    /// The `domain` half, after `@`.
    public var domain: String

    /// `id@domain`.
    public var address: String { "\(id)@\(domain)" }

    public init(id: String, domain: String) {
        self.id = id
        self.domain = domain
    }

    /// Splits an address on the last `@`.
    public init(address: String) throws {
        guard let separator = address.lastIndex(of: "@") else {
            throw GPXError(reason: .invalidValue(element: "email", value: address, expected: "an address in the form id@domain"))
        }
        let id = String(address[..<separator])
        let domain = String(address[address.index(after: separator)...])
        guard !id.isEmpty, !domain.isEmpty else {
            throw GPXError(reason: .invalidValue(element: "email", value: address, expected: "an address in the form id@domain"))
        }
        self.id = id
        self.domain = domain
    }

    func validate(version: GPX.Version) throws {
        try SchemaRules.checkText(id, element: "email")
        try SchemaRules.checkText(domain, element: "email")
        if version == .v1_0 {
            let pattern = #"^[\p{L}_]+(?:\.[\p{L}_]+)*@[\p{L}_]+(?:\.[\p{L}_]+)+$"#
            guard address.range(of: pattern, options: .regularExpression) != nil else {
                throw GPXError(
                    reason: .invalidValue(
                        element: "email",
                        value: address,
                        expected: "a GPX 1.0 address of letters and underscores, such as name@example.com"
                    )
                )
            }
        }
    }
}

/// GPX 1.1 copyright and license information.
public struct Copyright: Equatable, Sendable {
    /// Copyright holder. Required `author` attribute.
    public var author: String
    /// `year`.
    public var year: Int?
    /// `license` URI.
    public var license: String?

    public init(author: String, year: Int? = nil, license: String? = nil) {
        self.author = author
        self.year = year
        self.license = license
    }

    func validate() throws {
        try SchemaRules.checkText(author, element: "copyright")
        try SchemaRules.checkText(license, element: "license")
    }
}

/// A hyperlink. GPX 1.1 `link`, or GPX 1.0 `url` plus optional `urlname`.
public struct Link: Equatable, Sendable {
    /// `href`, or the GPX 1.0 `url`.
    public var href: String
    /// `text`, or the GPX 1.0 `urlname`.
    public var text: String?
    /// GPX 1.1 `type`. MIME type of the linked content.
    public var mimeType: String?

    public init(href: String, text: String? = nil, mimeType: String? = nil) {
        self.href = href
        self.text = text
        self.mimeType = mimeType
    }

    func validate(version: GPX.Version) throws {
        try SchemaRules.checkText(href, element: "href")
        try SchemaRules.checkText(text, element: "text")
        try SchemaRules.checkText(mimeType, element: "type")
        if version == .v1_0, mimeType != nil {
            throw GPXError(reason: .unsupportedInVersion(.v1_0, detail: "A link MIME type"))
        }
    }
}

/// Minimum and maximum latitude and longitude of the coordinates in the file.
public struct Bounds: Equatable, Sendable {
    public var minimumLatitude: Double
    public var minimumLongitude: Double
    public var maximumLatitude: Double
    public var maximumLongitude: Double

    public init(
        minimumLatitude: Double,
        minimumLongitude: Double,
        maximumLatitude: Double,
        maximumLongitude: Double
    ) {
        self.minimumLatitude = minimumLatitude
        self.minimumLongitude = minimumLongitude
        self.maximumLatitude = maximumLatitude
        self.maximumLongitude = maximumLongitude
    }

    func validate(version: GPX.Version) throws {
        try SchemaRules.checkLatitude(minimumLatitude, field: "minlat")
        try SchemaRules.checkLatitude(maximumLatitude, field: "maxlat")
        try SchemaRules.checkLongitude(minimumLongitude, version: version, field: "minlon")
        try SchemaRules.checkLongitude(maximumLongitude, version: version, field: "maxlon")
    }
}

/// Type of GPS fix. Omit the value when the fix is unknown.
public enum GPSFix: String, Equatable, Sendable, CaseIterable {
    case none
    /// Two-dimensional fix. XML value `2d`.
    case twoDimensional = "2d"
    /// Three-dimensional fix. XML value `3d`.
    case threeDimensional = "3d"
    case dgps
    /// Military signal used. XML value `pps`.
    case pps
}

/// Where a point is stored. Course and speed exist only on GPX 1.0 track points.
enum PointRole {
    case waypoint
    case routePoint
    case trackPoint
}

/// A waypoint, route point, or track point. All three use the same published fields, except GPX 1.0 track points, which also have course and speed.
public struct Waypoint: Equatable, Sendable {
    /// `lat`. Decimal degrees, WGS84, from -90 through 90.
    public var latitude: Double
    /// `lon`. Decimal degrees, WGS84. GPX 1.0 allows -180 through 180. GPX 1.1 allows -180 up to, but not including, 180.
    public var longitude: Double
    /// `ele`. Elevation in meters.
    public var elevation: Double?
    /// `time`.
    public var time: Date?
    /// `course`. True course in degrees. Published only on GPX 1.0 track points.
    public var course: Double?
    /// `speed`. Published only on GPX 1.0 track points. GPS software reads this as meters per second.
    public var speed: Double?
    /// `magvar`. Magnetic variation in degrees.
    public var magneticVariation: Double?
    /// `geoidheight`. Height of the geoid above the WGS84 ellipsoid, in meters.
    public var geoidHeight: Double?
    /// `name`.
    public var name: String?
    /// `cmt`.
    public var comment: String?
    /// `desc`.
    public var description: String?
    /// `src`.
    public var source: String?
    /// GPX 1.0 `url` and `urlname`, or GPX 1.1 `link` elements.
    public var links: [Link]
    /// `sym`.
    public var symbol: String?
    /// `type`.
    public var type: String?
    /// `fix`.
    public var fix: GPSFix?
    /// `sat`.
    public var satelliteCount: Int?
    /// `hdop`.
    public var horizontalDilution: Double?
    /// `vdop`.
    public var verticalDilution: Double?
    /// `pdop`.
    public var positionDilution: Double?
    /// `ageofdgpsdata`. Seconds since the last DGPS update.
    public var ageOfDGPSData: Double?
    /// `dgpsid`. DGPS station id, from 0 through 1023.
    public var dgpsStationID: Int?
    /// Extension elements.
    public var extensions: Extensions?

    public init(
        latitude: Double,
        longitude: Double,
        elevation: Double? = nil,
        time: Date? = nil,
        course: Double? = nil,
        speed: Double? = nil,
        magneticVariation: Double? = nil,
        geoidHeight: Double? = nil,
        name: String? = nil,
        comment: String? = nil,
        description: String? = nil,
        source: String? = nil,
        links: [Link] = [],
        symbol: String? = nil,
        type: String? = nil,
        fix: GPSFix? = nil,
        satelliteCount: Int? = nil,
        horizontalDilution: Double? = nil,
        verticalDilution: Double? = nil,
        positionDilution: Double? = nil,
        ageOfDGPSData: Double? = nil,
        dgpsStationID: Int? = nil,
        extensions: Extensions? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.time = time
        self.course = course
        self.speed = speed
        self.magneticVariation = magneticVariation
        self.geoidHeight = geoidHeight
        self.name = name
        self.comment = comment
        self.description = description
        self.source = source
        self.links = links
        self.symbol = symbol
        self.type = type
        self.fix = fix
        self.satelliteCount = satelliteCount
        self.horizontalDilution = horizontalDilution
        self.verticalDilution = verticalDilution
        self.positionDilution = positionDilution
        self.ageOfDGPSData = ageOfDGPSData
        self.dgpsStationID = dgpsStationID
        self.extensions = extensions
    }

    func validate(version: GPX.Version, role: PointRole) throws {
        try SchemaRules.checkLatitude(latitude, field: "lat")
        try SchemaRules.checkLongitude(longitude, version: version, field: "lon")
        if let magneticVariation {
            try SchemaRules.checkDegrees(magneticVariation, version: version, field: "magvar")
        }
        if let satelliteCount {
            try SchemaRules.checkNonNegative(satelliteCount, field: "sat")
        }
        if let dgpsStationID {
            try SchemaRules.checkDGPSStation(dgpsStationID)
        }
        try SchemaRules.checkText(name, element: "name")
        try SchemaRules.checkText(comment, element: "cmt")
        try SchemaRules.checkText(description, element: "desc")
        try SchemaRules.checkText(source, element: "src")
        try SchemaRules.checkText(symbol, element: "sym")
        try SchemaRules.checkText(type, element: "type")
        try SchemaRules.checkLinks(links, version: version, context: "point")
        try SchemaRules.checkExtensions(extensions, version: version, context: "point")

        if course != nil || speed != nil {
            guard version == .v1_0, role == .trackPoint else {
                let detail = role == .trackPoint
                    ? "A course or speed"
                    : "A course or speed on a waypoint or route point"
                throw GPXError(reason: .unsupportedInVersion(version, detail: detail))
            }
            if let course {
                try SchemaRules.checkDegrees(course, version: version, field: "course")
            }
        }
    }
}

/// An ordered list of turn points leading to a destination.
public struct Route: Equatable, Sendable {
    /// `name`.
    public var name: String?
    /// `cmt`.
    public var comment: String?
    /// `desc`.
    public var description: String?
    /// `src`.
    public var source: String?
    /// GPX 1.0 `url` and `urlname`, or GPX 1.1 `link` elements.
    public var links: [Link]
    /// `number`.
    public var number: Int?
    /// GPX 1.1 `type`.
    public var type: String?
    /// Extension elements.
    public var extensions: Extensions?
    /// `rtept` elements, in order.
    public var points: [Waypoint]

    public init(
        name: String? = nil,
        comment: String? = nil,
        description: String? = nil,
        source: String? = nil,
        links: [Link] = [],
        number: Int? = nil,
        type: String? = nil,
        extensions: Extensions? = nil,
        points: [Waypoint] = []
    ) {
        self.name = name
        self.comment = comment
        self.description = description
        self.source = source
        self.links = links
        self.number = number
        self.type = type
        self.extensions = extensions
        self.points = points
    }

    func validate(version: GPX.Version) throws {
        try SchemaRules.checkText(name, element: "name")
        try SchemaRules.checkText(comment, element: "cmt")
        try SchemaRules.checkText(description, element: "desc")
        try SchemaRules.checkText(source, element: "src")
        try SchemaRules.checkText(type, element: "type")
        try SchemaRules.checkLinks(links, version: version, context: "rte")
        if let number {
            try SchemaRules.checkNonNegative(number, field: "number")
        }
        if version == .v1_0, type != nil {
            throw GPXError(reason: .unsupportedInVersion(.v1_0, detail: "A route type"))
        }
        try SchemaRules.checkExtensions(extensions, version: version, context: "rte")
        for point in points {
            try point.validate(version: version, role: .routePoint)
        }
    }
}

/// An ordered list of points describing a recorded path.
public struct Track: Equatable, Sendable {
    /// `name`.
    public var name: String?
    /// `cmt`.
    public var comment: String?
    /// `desc`.
    public var description: String?
    /// `src`.
    public var source: String?
    /// GPX 1.0 `url` and `urlname`, or GPX 1.1 `link` elements.
    public var links: [Link]
    /// `number`.
    public var number: Int?
    /// GPX 1.1 `type`.
    public var type: String?
    /// Extension elements.
    public var extensions: Extensions?
    /// `trkseg` elements, in order.
    public var segments: [TrackSegment]

    public init(
        name: String? = nil,
        comment: String? = nil,
        description: String? = nil,
        source: String? = nil,
        links: [Link] = [],
        number: Int? = nil,
        type: String? = nil,
        extensions: Extensions? = nil,
        segments: [TrackSegment] = []
    ) {
        self.name = name
        self.comment = comment
        self.description = description
        self.source = source
        self.links = links
        self.number = number
        self.type = type
        self.extensions = extensions
        self.segments = segments
    }

    func validate(version: GPX.Version) throws {
        try SchemaRules.checkText(name, element: "name")
        try SchemaRules.checkText(comment, element: "cmt")
        try SchemaRules.checkText(description, element: "desc")
        try SchemaRules.checkText(source, element: "src")
        try SchemaRules.checkText(type, element: "type")
        try SchemaRules.checkLinks(links, version: version, context: "trk")
        if let number {
            try SchemaRules.checkNonNegative(number, field: "number")
        }
        if version == .v1_0, type != nil {
            throw GPXError(reason: .unsupportedInVersion(.v1_0, detail: "A track type"))
        }
        try SchemaRules.checkExtensions(extensions, version: version, context: "trk")
        for segment in segments {
            try segment.validate(version: version)
        }
    }
}

/// A continuous span of track points. Start a new segment when reception was lost or the receiver was turned off.
public struct TrackSegment: Equatable, Sendable {
    /// `trkpt` elements, in order.
    public var points: [Waypoint]
    /// GPX 1.1 segment `extensions`.
    public var extensions: Extensions?

    public init(points: [Waypoint] = [], extensions: Extensions? = nil) {
        self.points = points
        self.extensions = extensions
    }

    func validate(version: GPX.Version) throws {
        if version == .v1_0, extensions != nil {
            throw GPXError(reason: .unsupportedInVersion(.v1_0, detail: "Track segment extensions"))
        }
        try SchemaRules.checkExtensions(extensions, version: version, context: "trkseg")
        for point in points {
            try point.validate(version: version, role: .trackPoint)
        }
    }
}

/// Foreign-namespace elements from the schema's `extensions` element, or from GPX 1.0's `xsd:any` slots.
public struct Extensions: Equatable, Sendable {
    public var elements: [XMLElement]

    public init(elements: [XMLElement] = []) {
        self.elements = elements
    }
}

/// An XML attribute preserved on an extension element.
public struct XMLAttribute: Equatable, Sendable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// An element that is not part of the GPX schema, kept so extension data survives a read and write.
public struct XMLElement: Equatable, Sendable {
    public var name: String
    public var attributes: [XMLAttribute]
    public var children: [XMLNode]

    public init(name: String, attributes: [XMLAttribute] = [], children: [XMLNode] = []) {
        self.name = name
        self.attributes = attributes
        self.children = children
    }

    public init(name: String, attributes: [XMLAttribute] = [], text: String) {
        self.init(name: name, attributes: attributes, children: [.text(text)])
    }
}

/// A child of an extension element.
public enum XMLNode: Equatable, Sendable {
    case text(String)
    indirect case element(XMLElement)
}

enum SchemaRules {
    static func checkText(_ value: String?, element: String) throws {
        guard let value, XMLCodec.containsIllegalXMLCharacter(value) else { return }
        throw GPXError(reason: .invalidValue(element: element, value: value, expected: "text without illegal XML characters"))
    }

    static func checkLatitude(_ value: Double, field: String, display: String? = nil) throws {
        guard value.isFinite, (-90.0...90.0).contains(value) else {
            throw GPXError(reason: .invalidValue(element: field, value: display ?? String(value), expected: "a latitude from -90 through 90"))
        }
    }

    static func checkLongitude(_ value: Double, version: GPX.Version, field: String, display: String? = nil) throws {
        let upperIsValid = version == .v1_0 ? value <= 180 : value < 180
        guard value.isFinite, value >= -180, upperIsValid else {
            let expected = version == .v1_0
                ? "a longitude from -180 through 180"
                : "a longitude from -180 up to, but not including, 180"
            throw GPXError(reason: .invalidValue(element: field, value: display ?? String(value), expected: expected))
        }
    }

    static func checkDegrees(_ value: Double, version: GPX.Version, field: String, display: String? = nil) throws {
        let upperIsValid = version == .v1_0 ? value <= 360 : value < 360
        guard value.isFinite, value >= 0, upperIsValid else {
            let expected = version == .v1_0
                ? "degrees from 0 through 360"
                : "degrees from 0 up to, but not including, 360"
            throw GPXError(reason: .invalidValue(element: field, value: display ?? String(value), expected: expected))
        }
    }

    static func checkNonNegative(_ value: Int, field: String) throws {
        guard value >= 0 else {
            throw GPXError(reason: .invalidValue(element: field, value: String(value), expected: "a non-negative integer"))
        }
    }

    static func checkDGPSStation(_ value: Int) throws {
        guard (0...1023).contains(value) else {
            throw GPXError(reason: .invalidValue(element: "dgpsid", value: String(value), expected: "an integer from 0 through 1023"))
        }
    }

    static func checkLinks(_ links: [Link], version: GPX.Version, context: String) throws {
        if version == .v1_0, links.count > 1 {
            throw GPXError(reason: .unsupportedInVersion(.v1_0, detail: "More than one link on \(context)"))
        }
        for link in links {
            try link.validate(version: version)
        }
    }

    static func checkExtensions(_ extensions: Extensions?, version: GPX.Version, context: String) throws {
        guard let extensions else { return }
        for element in extensions.elements {
            try checkXMLName(element.name, element: context)
            if !XMLCodec.isForeignExtension(element, version: version) {
                throw GPXError(
                    reason: .invalidValue(
                        element: context,
                        value: element.name,
                        expected: "an element in a namespace other than \(version.namespaceURI), with its xmlns declaration on the element"
                    )
                )
            }
            try checkExtensionTree(element)
        }
    }

    private static func checkXMLName(_ name: String, element: String) throws {
        let illegal = name.isEmpty || name.contains { character in
            character.isWhitespace || "<>&\"'".contains(character)
        }
        if illegal {
            throw GPXError(reason: .invalidValue(element: element, value: name, expected: "an XML name"))
        }
    }

    private static func checkExtensionTree(_ element: XMLElement) throws {
        try checkXMLName(element.name, element: element.name)
        for attribute in element.attributes {
            try checkXMLName(attribute.name, element: element.name)
            try checkText(attribute.value, element: attribute.name)
        }
        for child in element.children {
            switch child {
            case .text(let text):
                try checkText(text, element: element.name)
            case .element(let child):
                try checkExtensionTree(child)
            }
        }
    }
}

/// A failure while reading or writing a GPX document.
public struct GPXError: Error, Equatable, Sendable, CustomStringConvertible {
    /// What went wrong.
    public enum Reason: Equatable, Sendable {
        case malformedXML(String)
        case unsupportedVersion(String)
        case missingAttribute(element: String, name: String)
        case unexpectedElement(String, parent: String)
        case duplicateElement(String, parent: String)
        case invalidValue(element: String, value: String, expected: String)
        case unsupportedInVersion(GPX.Version, detail: String)
    }

    public var reason: Reason
    /// 1-based line in the source XML, when the failure happened while parsing.
    public var line: Int?

    public init(reason: Reason, line: Int? = nil) {
        self.reason = reason
        self.line = line
    }

    public var description: String {
        let detail: String
        switch reason {
        case .malformedXML(let message):
            detail = message
        case .unsupportedVersion(let version):
            detail = "Unsupported GPX version \"\(version)\". Supported versions are 1.0 and 1.1."
        case .missingAttribute(let element, let name):
            detail = "Missing required attribute \(name) on \(element)."
        case .unexpectedElement(let element, let parent):
            detail = "Unexpected element \(element) in \(parent)."
        case .duplicateElement(let element, let parent):
            detail = "Duplicate element \(element) in \(parent)."
        case .invalidValue(let element, let value, let expected):
            detail = "Invalid value \"\(value)\" for \(element). Expected \(expected)."
        case .unsupportedInVersion(let version, let explanation):
            detail = "\(explanation) is not part of GPX \(version.rawValue)."
        }
        if let line {
            return "Line \(line): \(detail)"
        }
        return detail
    }
}
