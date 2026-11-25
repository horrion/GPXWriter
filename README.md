# GPXWriter

A Swift package that reads and writes [GPX](https://www.topografix.com/gpx.asp) files. It uses Foundation only.

GPX 1.0 (2002) and GPX 1.1 (2004) are the published TopoGrafix schemas. GPX 1.1 is the default. Every element and attribute in both schemas is represented. Writing a field that belongs only to the other version throws `GPXError` instead of dropping it.

## Use it

In Xcode, choose **File → Add Package Dependencies…**, click **Add Local…**, and select this folder. Add the **GPXWriter** library to your app target.

If the other project is a Swift package, depend on the path:

```swift
dependencies: [
    .package(path: "../GPXWriter")
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: ["GPXWriter"]
    )
]
```

```swift
import GPXWriter

let saved = try GPX(contentsOf: fileURL)

var log = GPX(version: .v1_0, creator: "LocatorGator")
log.tracks = [
    Track(segments: [
        TrackSegment(points: [
            Waypoint(
                latitude: 35.0185442384,
                longitude: -79.4639757277,
                elevation: 12.33,
                time: Date(),
                speed: 166.53,
                satelliteCount: 4
            )
        ])
    ])
]
try log.write(to: outputURL)
```

`GPX(xml:)` and `GPX(data:)` parse a document. `xml()` and `data()` serialize one. Pass `prettyPrinted: false` for a compact file.

## Versions

| | GPX 1.0 | GPX 1.1 |
| --- | --- | --- |
| File info | Direct children of `gpx` | Wrapped in `metadata` |
| Links | One `url` and optional `urlname` | One or more `link` elements, with optional text and MIME type |
| Author | Name and email strings | `author` with name, `id`/`domain` email, and a link |
| Copyright | | `copyright` |
| Track points | `course` and `speed` | |
| Extensions | Foreign-namespace elements in the schema's `xsd:any` slots | An `extensions` element |
| Longitude | −180 through 180 | −180 up to, but not including, 180 |
| Degrees | 0 through 360 | 0 up to, but not including, 360 |

Course and speed are valid only on a GPX 1.0 track point. Vendor data, such as a Garmin heart-rate extension, is stored on `extensions` and written back. Each top-level extension element must declare a namespace other than the GPX namespace.

`ptType` and `ptsegType` are types the GPX 1.1 schema publishes for other schemas. They are not elements of a GPX document.

## Build

Swift 6.4 or later.

```sh
swift test
```
