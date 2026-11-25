// Copyright © 2017-2026 Robert Horrion.

import Foundation

struct DocumentParser {
    func parse(_ data: Data) throws -> GPX {
        let parser = Parser()
        return try parser.parse(data)
    }
}

private final class Parser: NSObject, XMLParserDelegate {
    private final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    private final class Frame {
        let localName: String
        var text = ""
        var kind: Kind
        var seen = Set<String>()
        var legacyURL: String?
        var legacyURLName: String?
        var sawElementChild = false

        enum Kind {
            case gpx(Box<GPX>)
            case metadata(Box<Metadata>)
            case person(Box<Person>)
            case copyright(Box<Copyright>)
            case link(Box<Link>)
            case waypoint(Box<Waypoint>, PointRole)
            case route(Box<Route>)
            case track(Box<Track>)
            case segment(Box<TrackSegment>)
            case extensions(Box<Extensions>)
            case raw(Box<XMLElement>)
            case bounds(Bounds)
            case email(Email)
            case scalar
        }

        init(localName: String, kind: Kind) {
            self.localName = localName
            self.kind = kind
        }
    }

    private var stack: [Frame] = []
    private var namespaces: [[String: String]] = [[:]]
    private var documentVersion: GPX.Version?
    private var result: GPX?
    private var error: GPXError?
    private var xmlParser: XMLParser?

    func parse(_ data: Data) throws -> GPX {
        let xmlParser = XMLParser(data: data)
        xmlParser.shouldProcessNamespaces = false
        xmlParser.shouldResolveExternalEntities = false
        xmlParser.shouldReportNamespacePrefixes = false
        xmlParser.delegate = self
        self.xmlParser = xmlParser

        let parsed = xmlParser.parse()
        if let error {
            throw error
        }
        guard parsed, let document = result else {
            let message = xmlParser.parserError?.localizedDescription ?? "The XML could not be parsed."
            throw GPXError(reason: .malformedXML(message), line: xmlParser.lineNumber)
        }
        do {
            try document.validate()
        } catch let validation as GPXError {
            throw validation
        }
        return document
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard error == nil else { return }
        let local = XMLCodec.localName(elementName)

        if let parent = stack.last, isOpaqueContainer(parent) {
            if case .raw = parent.kind {
                flushRawText(parent)
            }
            pushNamespaces(attributeDict)
            let element = XMLElement(name: elementName, attributes: xmlAttributes(attributeDict))
            stack.append(Frame(localName: elementName, kind: .raw(Box(element))))
            return
        }

        pushNamespaces(attributeDict)
        var appended = false
        defer {
            if !appended {
                popNamespaces()
            }
        }

        if let parent = stack.last, !discardInterElementText(parent) {
            return
        }

        if isForeign(elementName) {
            guard let parent = stack.last, acceptsForeign(parent) else {
                fail(.unexpectedElement(local, parent: stack.last?.localName ?? "document"))
                return
            }
            let element = XMLElement(name: elementName, attributes: xmlAttributes(attributeDict))
            stack.append(Frame(localName: elementName, kind: .raw(Box(element))))
            appended = true
            return
        }

        if stack.isEmpty {
            guard result == nil, local == "gpx" else {
                fail(.unexpectedElement(local, parent: "document"))
                return
            }
            let depth = stack.count
            startGPX(attributeDict)
            appended = stack.count > depth
            return
        }

        guard let parent = stack.last else { return }
        guard claim(local, on: parent) else { return }
        let depth = stack.count
        openChild(local, attributes: attributeDict, parent: parent)
        appended = stack.count > depth
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard error == nil else { return }
        stack.last?.text += string
    }

    func parser(_ parser: XMLParser, foundIgnorableWhitespace whitespaceString: String) {
        self.parser(parser, foundCharacters: whitespaceString)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let string = String(data: CDATABlock, encoding: .utf8) else { return }
        self.parser(parser, foundCharacters: string)
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if error == nil {
            error = GPXError(reason: .malformedXML(parseError.localizedDescription), line: parser.lineNumber)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard error == nil, let frame = stack.popLast() else { return }
        popNamespaces()

        switch frame.kind {
        case .scalar:
            applyScalar(frame)
        case .gpx(let box):
            if let link = consumeLegacyLink(on: frame) {
                box.value.metadata.links.append(link)
            }
            guard error == nil else { return }
            guard rejectMixedContent(frame) else { return }
            result = box.value
        case .metadata(let box):
            guard rejectMixedContent(frame) else { return }
            guard let parent = stack.last, case .gpx(let gpx) = parent.kind else {
                fail(.unexpectedElement("metadata", parent: stack.last?.localName ?? "document"))
                return
            }
            gpx.value.metadata = box.value
        case .person(let box):
            guard rejectMixedContent(frame) else { return }
            guard let parent = stack.last, case .metadata(let metadata) = parent.kind else {
                fail(.unexpectedElement("author", parent: stack.last?.localName ?? "document"))
                return
            }
            metadata.value.author = box.value
        case .copyright(let box):
            guard rejectMixedContent(frame) else { return }
            guard let parent = stack.last, case .metadata(let metadata) = parent.kind else {
                fail(.unexpectedElement("copyright", parent: stack.last?.localName ?? "document"))
                return
            }
            metadata.value.copyright = box.value
        case .link(let box):
            guard rejectMixedContent(frame) else { return }
            attachLink(box.value)
        case .email(let email):
            guard rejectMixedContent(frame) else { return }
            guard let parent = stack.last, case .person(let person) = parent.kind else {
                fail(.unexpectedElement("email", parent: stack.last?.localName ?? "document"))
                return
            }
            person.value.email = email
        case .bounds(let bounds):
            guard rejectMixedContent(frame) else { return }
            guard let parent = stack.last else { return }
            switch parent.kind {
            case .gpx(let box):
                box.value.metadata.bounds = bounds
            case .metadata(let box):
                box.value.bounds = bounds
            default:
                fail(.unexpectedElement("bounds", parent: parent.localName))
            }
        case .waypoint(let box, let role):
            if let link = consumeLegacyLink(on: frame) {
                box.value.links.append(link)
            }
            guard error == nil, rejectMixedContent(frame) else { return }
            attachWaypoint(box.value, role: role)
        case .route(let box):
            if let link = consumeLegacyLink(on: frame) {
                box.value.links.append(link)
            }
            guard error == nil, rejectMixedContent(frame) else { return }
            guard let parent = stack.last, case .gpx(let gpx) = parent.kind else {
                fail(.unexpectedElement("rte", parent: stack.last?.localName ?? "document"))
                return
            }
            gpx.value.routes.append(box.value)
        case .track(let box):
            if let link = consumeLegacyLink(on: frame) {
                box.value.links.append(link)
            }
            guard error == nil, rejectMixedContent(frame) else { return }
            guard let parent = stack.last, case .gpx(let gpx) = parent.kind else {
                fail(.unexpectedElement("trk", parent: stack.last?.localName ?? "document"))
                return
            }
            gpx.value.tracks.append(box.value)
        case .segment(let box):
            guard rejectMixedContent(frame) else { return }
            guard let parent = stack.last, case .track(let track) = parent.kind else {
                fail(.unexpectedElement("trkseg", parent: stack.last?.localName ?? "document"))
                return
            }
            track.value.segments.append(box.value)
        case .extensions(let box):
            guard rejectMixedContent(frame) else { return }
            guard !box.value.elements.isEmpty else { return }
            guard let parent = stack.last else { return }
            switch parent.kind {
            case .gpx(let parentBox):
                merge(box.value, into: &parentBox.value.extensions)
            case .metadata(let parentBox):
                merge(box.value, into: &parentBox.value.extensions)
            case .waypoint(let parentBox, _):
                merge(box.value, into: &parentBox.value.extensions)
            case .route(let parentBox):
                merge(box.value, into: &parentBox.value.extensions)
            case .track(let parentBox):
                merge(box.value, into: &parentBox.value.extensions)
            case .segment(let parentBox):
                merge(box.value, into: &parentBox.value.extensions)
            default:
                fail(.unexpectedElement("extensions", parent: parent.localName))
            }
        case .raw(let box):
            finishRawText(frame, box: box)
            guard let parent = stack.last else { return }
            if case .raw(let parentBox) = parent.kind {
                parentBox.value.children.append(.element(box.value))
            } else {
                let namespace = documentVersion?.namespaceURI ?? GPX.Version.v1_1.namespaceURI
                let element = XMLCodec.declaringInheritedNamespaces(
                    box.value,
                    parentScope: namespaces.last ?? [:],
                    documentNamespace: namespace
                )
                attachExtension(element)
            }
        }
    }

    private func startGPX(_ attributes: [String: String]) {
        guard let versionString = attribute("version", in: attributes) else {
            fail(.missingAttribute(element: "gpx", name: "version"))
            return
        }
        guard let version = GPX.Version(rawValue: versionString) else {
            fail(.unsupportedVersion(versionString))
            return
        }
        guard let creator = attribute("creator", in: attributes) else {
            fail(.missingAttribute(element: "gpx", name: "creator"))
            return
        }
        guard !XMLCodec.containsIllegalXMLCharacter(creator) else {
            fail(.invalidValue(element: "creator", value: creator, expected: "text without illegal XML characters"))
            return
        }
        documentVersion = version
        stack.append(Frame(localName: "gpx", kind: .gpx(Box(GPX(version: version, creator: creator)))))
    }

    private func openChild(_ local: String, attributes: [String: String], parent: Frame) {
        switch parent.kind {
        case .gpx:
            openGPXChild(local, attributes)
        case .metadata:
            openMetadataChild(local, attributes)
        case .person:
            openPersonChild(local, attributes)
        case .copyright:
            switch local {
            case "year", "license": openScalar(local)
            default: fail(.unexpectedElement(local, parent: "copyright"))
            }
        case .link:
            switch local {
            case "text", "type": openScalar(local)
            default: fail(.unexpectedElement(local, parent: "link"))
            }
        case .waypoint(_, let role):
            openPointChild(local, role: role, attributes: attributes)
        case .route:
            openRouteChild(local, attributes)
        case .track:
            openTrackChild(local, attributes)
        case .segment:
            openSegmentChild(local, attributes)
        case .bounds, .email, .scalar, .extensions, .raw:
            fail(.unexpectedElement(local, parent: parent.localName))
        }
    }

    private func openGPXChild(_ local: String, _ attributes: [String: String]) {
        guard let version = documentVersion else { return }
        switch version {
        case .v1_0:
            switch local {
            case "name", "desc", "author", "email", "url", "urlname", "time", "keywords":
                openScalar(local)
            case "bounds":
                openBounds(attributes)
            case "wpt":
                openPoint(local, attributes, role: .waypoint)
            case "rte":
                stack.append(Frame(localName: local, kind: .route(Box(Route()))))
            case "trk":
                stack.append(Frame(localName: local, kind: .track(Box(Track()))))
            default:
                fail(.unexpectedElement(local, parent: "gpx"))
            }
        case .v1_1:
            switch local {
            case "metadata":
                stack.append(Frame(localName: local, kind: .metadata(Box(Metadata()))))
            case "wpt":
                openPoint(local, attributes, role: .waypoint)
            case "rte":
                stack.append(Frame(localName: local, kind: .route(Box(Route()))))
            case "trk":
                stack.append(Frame(localName: local, kind: .track(Box(Track()))))
            case "extensions":
                openExtensions()
            default:
                fail(.unexpectedElement(local, parent: "gpx"))
            }
        }
    }

    private func openMetadataChild(_ local: String, _ attributes: [String: String]) {
        switch local {
        case "name", "desc", "time", "keywords":
            openScalar(local)
        case "author":
            stack.append(Frame(localName: local, kind: .person(Box(Person()))))
        case "copyright":
            guard let author = attribute("author", in: attributes) else {
                fail(.missingAttribute(element: "copyright", name: "author"))
                return
            }
            stack.append(Frame(localName: local, kind: .copyright(Box(Copyright(author: author)))))
        case "link":
            openLink(attributes)
        case "bounds":
            openBounds(attributes)
        case "extensions":
            openExtensions()
        default:
            fail(.unexpectedElement(local, parent: "metadata"))
        }
    }

    private func openPersonChild(_ local: String, _ attributes: [String: String]) {
        switch local {
        case "name":
            openScalar(local)
        case "email":
            guard let id = attribute("id", in: attributes) else {
                fail(.missingAttribute(element: "email", name: "id"))
                return
            }
            guard let domain = attribute("domain", in: attributes) else {
                fail(.missingAttribute(element: "email", name: "domain"))
                return
            }
            let email = Email(id: id, domain: domain)
            guard catching({ try email.validate(version: documentVersion ?? .v1_1) }) else { return }
            stack.append(Frame(localName: local, kind: .email(email)))
        case "link":
            openLink(attributes)
        default:
            fail(.unexpectedElement(local, parent: "author"))
        }
    }

    private func openPointChild(_ local: String, role: PointRole, attributes: [String: String]) {
        guard let version = documentVersion else { return }
        switch local {
        case "ele", "time", "magvar", "geoidheight", "name", "cmt", "desc", "src", "sym", "type",
             "fix", "sat", "hdop", "vdop", "pdop", "ageofdgpsdata", "dgpsid":
            openScalar(local)
        case "course", "speed":
            if version == .v1_0, role == .trackPoint {
                openScalar(local)
            } else {
                fail(.unexpectedElement(local, parent: pointParentName(role)))
            }
        case "url", "urlname":
            if version == .v1_0 { openScalar(local) } else { fail(.unexpectedElement(local, parent: pointParentName(role))) }
        case "link":
            if version == .v1_1 { openLink(attributes) } else { fail(.unexpectedElement(local, parent: pointParentName(role))) }
        case "extensions":
            if version == .v1_1 { openExtensions() } else { fail(.unexpectedElement(local, parent: pointParentName(role))) }
        default:
            fail(.unexpectedElement(local, parent: pointParentName(role)))
        }
    }

    private func openRouteChild(_ local: String, _ attributes: [String: String]) {
        guard let version = documentVersion else { return }
        switch local {
        case "name", "cmt", "desc", "src", "number":
            openScalar(local)
        case "url", "urlname":
            if version == .v1_0 { openScalar(local) } else { fail(.unexpectedElement(local, parent: "rte")) }
        case "link":
            if version == .v1_1 { openLink(attributes) } else { fail(.unexpectedElement(local, parent: "rte")) }
        case "type":
            if version == .v1_1 { openScalar(local) } else { fail(.unexpectedElement(local, parent: "rte")) }
        case "extensions":
            if version == .v1_1 { openExtensions() } else { fail(.unexpectedElement(local, parent: "rte")) }
        case "rtept":
            openPoint(local, attributes, role: .routePoint)
        default:
            fail(.unexpectedElement(local, parent: "rte"))
        }
    }

    private func openTrackChild(_ local: String, _ attributes: [String: String]) {
        guard let version = documentVersion else { return }
        switch local {
        case "name", "cmt", "desc", "src", "number":
            openScalar(local)
        case "url", "urlname":
            if version == .v1_0 { openScalar(local) } else { fail(.unexpectedElement(local, parent: "trk")) }
        case "link":
            if version == .v1_1 { openLink(attributes) } else { fail(.unexpectedElement(local, parent: "trk")) }
        case "type":
            if version == .v1_1 { openScalar(local) } else { fail(.unexpectedElement(local, parent: "trk")) }
        case "extensions":
            if version == .v1_1 { openExtensions() } else { fail(.unexpectedElement(local, parent: "trk")) }
        case "trkseg":
            stack.append(Frame(localName: local, kind: .segment(Box(TrackSegment()))))
        default:
            fail(.unexpectedElement(local, parent: "trk"))
        }
    }

    private func openSegmentChild(_ local: String, _ attributes: [String: String]) {
        guard let version = documentVersion else { return }
        switch local {
        case "trkpt":
            openPoint(local, attributes, role: .trackPoint)
        case "extensions":
            if version == .v1_1 { openExtensions() } else { fail(.unexpectedElement(local, parent: "trkseg")) }
        default:
            fail(.unexpectedElement(local, parent: "trkseg"))
        }
    }

    private func openPoint(_ local: String, _ attributes: [String: String], role: PointRole) {
        guard let version = documentVersion else { return }
        guard let latitudeRaw = attribute("lat", in: attributes) else {
            fail(.missingAttribute(element: local, name: "lat"))
            return
        }
        guard let longitudeRaw = attribute("lon", in: attributes) else {
            fail(.missingAttribute(element: local, name: "lon"))
            return
        }
        guard let latitude = catching({ try XMLCodec.decimal(latitudeRaw, element: "lat") }),
              let longitude = catching({ try XMLCodec.decimal(longitudeRaw, element: "lon") }),
              catching({ try SchemaRules.checkLatitude(latitude, field: "lat", display: latitudeRaw) }),
              catching({ try SchemaRules.checkLongitude(longitude, version: version, field: "lon", display: longitudeRaw) })
        else { return }
        let point = Waypoint(latitude: latitude, longitude: longitude)
        stack.append(Frame(localName: local, kind: .waypoint(Box(point), role)))
    }

    private func openBounds(_ attributes: [String: String]) {
        guard let version = documentVersion,
              let minLat = requiredDecimal("minlat", attributes, element: "bounds"),
              let minLon = requiredDecimal("minlon", attributes, element: "bounds"),
              let maxLat = requiredDecimal("maxlat", attributes, element: "bounds"),
              let maxLon = requiredDecimal("maxlon", attributes, element: "bounds"),
              catching({ try SchemaRules.checkLatitude(minLat, field: "minlat", display: attribute("minlat", in: attributes)) }),
              catching({ try SchemaRules.checkLongitude(minLon, version: version, field: "minlon", display: attribute("minlon", in: attributes)) }),
              catching({ try SchemaRules.checkLatitude(maxLat, field: "maxlat", display: attribute("maxlat", in: attributes)) }),
              catching({ try SchemaRules.checkLongitude(maxLon, version: version, field: "maxlon", display: attribute("maxlon", in: attributes)) })
        else { return }
        let bounds = Bounds(
            minimumLatitude: minLat,
            minimumLongitude: minLon,
            maximumLatitude: maxLat,
            maximumLongitude: maxLon
        )
        stack.append(Frame(localName: "bounds", kind: .bounds(bounds)))
    }

    private func openLink(_ attributes: [String: String]) {
        guard let href = attribute("href", in: attributes) else {
            fail(.missingAttribute(element: "link", name: "href"))
            return
        }
        stack.append(Frame(localName: "link", kind: .link(Box(Link(href: href)))))
    }

    private func openExtensions() {
        stack.append(Frame(localName: "extensions", kind: .extensions(Box(Extensions()))))
    }

    private func openScalar(_ local: String) {
        stack.append(Frame(localName: local, kind: .scalar))
    }

    private func applyScalar(_ frame: Frame) {
        let text = frame.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !XMLCodec.containsIllegalXMLCharacter(text) else {
            fail(.invalidValue(element: frame.localName, value: text, expected: "text without illegal XML characters"))
            return
        }
        guard let parent = stack.last else {
            fail(.unexpectedElement(frame.localName, parent: "document"))
            return
        }
        switch parent.kind {
        case .gpx(let box):
            applyFileField(frame.localName, text, gpx: box, frame: parent)
        case .metadata(let box):
            applyMetadataField(frame.localName, text, metadata: box)
        case .person(let box):
            if frame.localName == "name" {
                box.value.name = text
            }
        case .copyright(let box):
            applyCopyrightField(frame.localName, text, copyright: box)
        case .link(let box):
            switch frame.localName {
            case "text": box.value.text = text
            case "type": box.value.mimeType = text
            default: break
            }
        case .waypoint(let box, _):
            applyPointField(frame.localName, text, point: box)
        case .route(let box):
            applyRouteField(frame.localName, text, route: box, frame: parent)
        case .track(let box):
            applyTrackField(frame.localName, text, track: box, frame: parent)
        default:
            fail(.unexpectedElement(frame.localName, parent: parent.localName))
        }
    }

    private func applyFileField(_ name: String, _ text: String, gpx: Box<GPX>, frame: Frame) {
        switch name {
        case "name":
            gpx.value.metadata.name = text
        case "desc":
            gpx.value.metadata.description = text
        case "author":
            if gpx.value.metadata.author == nil { gpx.value.metadata.author = Person() }
            gpx.value.metadata.author?.name = text
        case "email":
            guard let email = catching({ try Email(address: text) }),
                  let version = documentVersion,
                  catching({ try email.validate(version: version) })
            else { return }
            if gpx.value.metadata.author == nil { gpx.value.metadata.author = Person() }
            gpx.value.metadata.author?.email = email
        case "url":
            frame.legacyURL = text
        case "urlname":
            frame.legacyURLName = text
        case "time":
            guard let time = catching({ try XMLCodec.date(text, element: "time") }) else { return }
            gpx.value.metadata.time = time
        case "keywords":
            gpx.value.metadata.keywords = text
        default:
            break
        }
    }

    private func applyMetadataField(_ name: String, _ text: String, metadata: Box<Metadata>) {
        switch name {
        case "name":
            metadata.value.name = text
        case "desc":
            metadata.value.description = text
        case "time":
            guard let time = catching({ try XMLCodec.date(text, element: "time") }) else { return }
            metadata.value.time = time
        case "keywords":
            metadata.value.keywords = text
        default:
            break
        }
    }

    private func applyCopyrightField(_ name: String, _ text: String, copyright: Box<Copyright>) {
        switch name {
        case "year":
            guard let year = catching({ try XMLCodec.year(text, element: "year") }) else { return }
            copyright.value.year = year
        case "license":
            copyright.value.license = text
        default:
            break
        }
    }

    private func applyPointField(_ name: String, _ text: String, point: Box<Waypoint>) {
        switch name {
        case "ele":
            point.value.elevation = catching { try XMLCodec.decimal(text, element: "ele") }
        case "time":
            point.value.time = catching { try XMLCodec.date(text, element: "time") }
        case "course":
            guard let course = catching({ try XMLCodec.decimal(text, element: "course") }),
                  let version = documentVersion,
                  catching({ try SchemaRules.checkDegrees(course, version: version, field: "course", display: text) })
            else { return }
            point.value.course = course
        case "speed":
            point.value.speed = catching { try XMLCodec.decimal(text, element: "speed") }
        case "magvar":
            guard let magvar = catching({ try XMLCodec.decimal(text, element: "magvar") }),
                  let version = documentVersion,
                  catching({ try SchemaRules.checkDegrees(magvar, version: version, field: "magvar", display: text) })
            else { return }
            point.value.magneticVariation = magvar
        case "geoidheight":
            point.value.geoidHeight = catching { try XMLCodec.decimal(text, element: "geoidheight") }
        case "name":
            point.value.name = text
        case "cmt":
            point.value.comment = text
        case "desc":
            point.value.description = text
        case "src":
            point.value.source = text
        case "url":
            stack.last?.legacyURL = text
        case "urlname":
            stack.last?.legacyURLName = text
        case "sym":
            point.value.symbol = text
        case "type":
            point.value.type = text
        case "fix":
            guard let fix = GPSFix(rawValue: text) else {
                fail(.invalidValue(element: "fix", value: text, expected: "none, 2d, 3d, dgps, or pps"))
                return
            }
            point.value.fix = fix
        case "sat":
            point.value.satelliteCount = catching { try XMLCodec.nonNegativeInteger(text, element: "sat") }
        case "hdop":
            point.value.horizontalDilution = catching { try XMLCodec.decimal(text, element: "hdop") }
        case "vdop":
            point.value.verticalDilution = catching { try XMLCodec.decimal(text, element: "vdop") }
        case "pdop":
            point.value.positionDilution = catching { try XMLCodec.decimal(text, element: "pdop") }
        case "ageofdgpsdata":
            point.value.ageOfDGPSData = catching { try XMLCodec.decimal(text, element: "ageofdgpsdata") }
        case "dgpsid":
            guard let identifier = catching({ try XMLCodec.integer(text, element: "dgpsid") }),
                  catching({ try SchemaRules.checkDGPSStation(identifier) })
            else { return }
            point.value.dgpsStationID = identifier
        default:
            break
        }
    }

    private func applyRouteField(_ name: String, _ text: String, route: Box<Route>, frame: Frame) {
        switch name {
        case "name": route.value.name = text
        case "cmt": route.value.comment = text
        case "desc": route.value.description = text
        case "src": route.value.source = text
        case "url": frame.legacyURL = text
        case "urlname": frame.legacyURLName = text
        case "number":
            route.value.number = catching { try XMLCodec.nonNegativeInteger(text, element: "number") }
        case "type": route.value.type = text
        default: break
        }
    }

    private func applyTrackField(_ name: String, _ text: String, track: Box<Track>, frame: Frame) {
        switch name {
        case "name": track.value.name = text
        case "cmt": track.value.comment = text
        case "desc": track.value.description = text
        case "src": track.value.source = text
        case "url": frame.legacyURL = text
        case "urlname": frame.legacyURLName = text
        case "number":
            track.value.number = catching { try XMLCodec.nonNegativeInteger(text, element: "number") }
        case "type": track.value.type = text
        default: break
        }
    }

    private func attachWaypoint(_ waypoint: Waypoint, role: PointRole) {
        guard let parent = stack.last else { return }
        switch (parent.kind, role) {
        case (.gpx(let box), .waypoint):
            box.value.waypoints.append(waypoint)
        case (.route(let box), .routePoint):
            box.value.points.append(waypoint)
        case (.segment(let box), .trackPoint):
            box.value.points.append(waypoint)
        default:
            fail(.unexpectedElement(pointParentName(role), parent: parent.localName))
        }
    }

    private func attachLink(_ link: Link) {
        guard let parent = stack.last else { return }
        switch parent.kind {
        case .metadata(let box):
            box.value.links.append(link)
        case .person(let box):
            box.value.link = link
        case .waypoint(let box, _):
            box.value.links.append(link)
        case .route(let box):
            box.value.links.append(link)
        case .track(let box):
            box.value.links.append(link)
        default:
            fail(.unexpectedElement("link", parent: parent.localName))
        }
    }

    private func attachExtension(_ element: XMLElement) {
        guard let parent = stack.last else { return }
        switch parent.kind {
        case .gpx(let box):
            merge(Extensions(elements: [element]), into: &box.value.extensions)
        case .metadata(let box):
            merge(Extensions(elements: [element]), into: &box.value.extensions)
        case .waypoint(let box, _):
            merge(Extensions(elements: [element]), into: &box.value.extensions)
        case .route(let box):
            merge(Extensions(elements: [element]), into: &box.value.extensions)
        case .track(let box):
            merge(Extensions(elements: [element]), into: &box.value.extensions)
        case .segment(let box):
            merge(Extensions(elements: [element]), into: &box.value.extensions)
        case .extensions(let box):
            box.value.elements.append(element)
        default:
            fail(.unexpectedElement(XMLCodec.localName(element.name), parent: parent.localName))
        }
    }

    private func merge(_ incoming: Extensions, into existing: inout Extensions?) {
        var combined = existing ?? Extensions()
        combined.elements.append(contentsOf: incoming.elements)
        existing = combined
    }

    private func consumeLegacyLink(on frame: Frame) -> Link? {
        guard frame.legacyURL != nil || frame.legacyURLName != nil else { return nil }
        guard let href = frame.legacyURL else {
            fail(.invalidValue(element: "urlname", value: frame.legacyURLName ?? "", expected: "a url on the same element"))
            return nil
        }
        return Link(href: href, text: frame.legacyURLName)
    }

    private func claim(_ local: String, on parent: Frame) -> Bool {
        guard !allowsMany(local, parent: parent) else { return true }
        if parent.seen.contains(local) {
            fail(.duplicateElement(local, parent: parent.localName))
            return false
        }
        parent.seen.insert(local)
        return true
    }

    private func allowsMany(_ local: String, parent: Frame) -> Bool {
        switch parent.kind {
        case .gpx:
            return local == "wpt" || local == "rte" || local == "trk"
        case .metadata, .waypoint:
            return local == "link"
        case .route:
            return local == "rtept"
        case .track:
            return local == "trkseg"
        case .segment:
            return local == "trkpt"
        default:
            return false
        }
    }

    private func acceptsForeign(_ frame: Frame) -> Bool {
        switch frame.kind {
        case .gpx, .metadata, .waypoint, .route, .track:
            return true
        case .segment:
            return documentVersion == .v1_1
        default:
            return false
        }
    }

    private func isOpaqueContainer(_ frame: Frame) -> Bool {
        switch frame.kind {
        case .raw, .extensions:
            return true
        default:
            return false
        }
    }

    private func isForeign(_ rawName: String) -> Bool {
        let scope = namespaces.last ?? [:]
        let namespace: String
        if let prefix = XMLCodec.prefix(of: rawName) {
            namespace = scope[prefix] ?? ""
        } else {
            namespace = scope[""] ?? ""
        }
        if namespace.isEmpty { return false }
        return namespace != GPX.Version.v1_0.namespaceURI && namespace != GPX.Version.v1_1.namespaceURI
    }

    private func pointParentName(_ role: PointRole) -> String {
        switch role {
        case .waypoint: "wpt"
        case .routePoint: "rtept"
        case .trackPoint: "trkpt"
        }
    }

    private func discardInterElementText(_ frame: Frame) -> Bool {
        if frame.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            frame.text = ""
            return true
        }
        fail(.invalidValue(element: frame.localName, value: frame.text, expected: "child elements rather than mixed text"))
        return false
    }

    @discardableResult
    private func rejectMixedContent(_ frame: Frame) -> Bool {
        discardInterElementText(frame)
    }

    private func flushRawText(_ frame: Frame) {
        guard case .raw(let box) = frame.kind else { return }
        let text = frame.text
        frame.text = ""
        frame.sawElementChild = true
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            box.value.children.append(.text(text))
        }
    }

    private func finishRawText(_ frame: Frame, box: Box<XMLElement>) {
        let text = frame.text
        if frame.sawElementChild {
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                box.value.children.append(.text(text))
            }
        } else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                box.value.children.append(.text(trimmed))
            }
        }
    }

    private func pushNamespaces(_ attributes: [String: String]) {
        var scope = namespaces.last ?? [:]
        for (key, value) in attributes {
            if key == "xmlns" {
                scope[""] = value
            } else if key.hasPrefix("xmlns:") {
                let prefix = String(key.dropFirst(6))
                if !prefix.isEmpty {
                    scope[prefix] = value
                }
            }
        }
        namespaces.append(scope)
    }

    private func popNamespaces() {
        if namespaces.count > 1 {
            namespaces.removeLast()
        }
    }

    private func xmlAttributes(_ attributes: [String: String]) -> [XMLAttribute] {
        attributes.map { XMLAttribute(name: $0.key, value: $0.value) }
    }

    private func attribute(_ name: String, in attributes: [String: String]) -> String? {
        if let value = attributes[name] {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for (key, value) in attributes where !key.hasPrefix("xmlns") && XMLCodec.localName(key) == name {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func requiredDecimal(_ name: String, _ attributes: [String: String], element: String) -> Double? {
        guard let raw = attribute(name, in: attributes) else {
            fail(.missingAttribute(element: element, name: name))
            return nil
        }
        return catching { try XMLCodec.decimal(raw, element: name) }
    }

    private func fail(_ reason: GPXError.Reason) {
        fail(GPXError(reason: reason, line: xmlParser?.lineNumber))
    }

    private func fail(_ gpxError: GPXError) {
        guard error == nil else { return }
        var copy = gpxError
        if copy.line == nil {
            copy.line = xmlParser?.lineNumber
        }
        error = copy
        xmlParser?.abortParsing()
    }

    private func catching(_ body: () throws -> Void) -> Bool {
        do {
            try body()
            return true
        } catch let gpxError as GPXError {
            fail(gpxError)
            return false
        } catch {
            fail(.malformedXML(String(describing: error)))
            return false
        }
    }

    private func catching<T>(_ body: () throws -> T) -> T? {
        do {
            return try body()
        } catch let gpxError as GPXError {
            fail(gpxError)
            return nil
        } catch {
            fail(.malformedXML(String(describing: error)))
            return nil
        }
    }
}
