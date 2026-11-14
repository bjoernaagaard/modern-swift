# Logging (digest)

Read the digest when you add logs or diagnostics to code that runs on an Apple platform.
A command line tool still writes its own output with `print`. A package that also runs
on Linux uses the `swift-log` package, which has the same levels.

Create one `Logger` per subsystem and category, and keep the log calls in shipping code.
Log events and failures, not the entry and exit of each function.
The system stores a message in a compact form and builds the text only when someone
reads the log, so a call costs little.

```swift
import os

let networkLog = Logger(subsystem: "com.example.shop", category: "network")

func finished(requestID: String, user: String, status: Int, seconds: Double) {
  networkLog.info(
    "request \(requestID, privacy: .public) status \(status) in \(seconds, format: .fixed(precision: 2))s"
  )
  networkLog.debug("user \(user, privacy: .private(mask: .hash))")
}
```

## Privacy

The system redacts an interpolated string or object unless you mark it. Numbers are
public by default.

| Marker | Result in the log | Use for |
|---|---|---|
| none, on a `String` | `<private>` | personal data |
| `privacy: .public` | the value | identifiers that are not personal, e.g., a request ID |
| `privacy: .private(mask: .hash)` | a stable hash | values you must match across lines without reading them |

## Levels

| Level | Stored on disk | Use for |
|---|---|---|
| `debug` | no | detail you read only while you develop |
| `info` | only when collected with a tool | helpful but not required detail |
| `notice` | yes | the default for events you need when you investigate a problem |
| `error` | yes | a failed operation |
| `fault` | yes, and kept longest | a bug in the program |

## Correlating one failure

Log one identifier on every line that belongs to one operation, e.g., a request UUID.
You can then filter the lines of a failed operation out of a log archive without
reproducing the failure. Collect an archive from a device with
`log collect --device --last 1h`, and open the archive in Console.
