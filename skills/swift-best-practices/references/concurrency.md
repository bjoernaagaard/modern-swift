# Concurrency (digest)

Sources: the Swift 6 migration guide at https://www.swift.org/migration/ and *The Swift
Programming Language*, chapter "Concurrency". Read the digest when section 5 of
`SKILL.md` does not settle a data race or isolation error, when you bridge a callback or
delegate API, or when you move a target to the Swift 6 language mode.

## Reading an isolation error

The compiler assigns every declaration to one isolation domain. A domain is the main
actor, one actor instance, or `nonisolated`. An error means a value that is not
`Sendable` would be used from two domains.

| Error text contains | Usual cause | First fix to try |
|---|---|---|
| "var ... is not concurrency-safe because it is nonisolated global shared mutable state" | a `var` global or static | make it a `let`, or mark it `@MainActor` |
| "sending ... risks causing data races" | a non-`Sendable` value is used after it was passed to another domain | finish all changes before the call, and don't use the value afterward |
| "main actor-isolated ... can not be referenced from a nonisolated context" | a `nonisolated` function reads main actor state | pass the value as a parameter, or move the function to the main actor |
| "capture of ... with non-Sendable type in a `@Sendable` closure" | a closure that runs elsewhere captures a class instance | capture the one value the closure needs in its capture list |
| "conformance of ... to protocol ... crosses into main actor-isolated code" | a main actor type conforms to a `nonisolated` protocol | write the conformance as `extension T: @MainActor P` |

The most common fix is to stop sharing. A class with mutable state is not `Sendable`, so
two child tasks cannot use one instance. Give each child task its own instance.

```swift
final class Scaler {
  var scratch: [UInt8] = []
  func shrink(_ data: [UInt8]) -> [UInt8] {
    scratch = Array(data.prefix(16))
    return scratch
  }
}

func thumbnails(_ first: [UInt8], _ second: [UInt8]) async -> ([UInt8], [UInt8]) {
  // Outside the main actor, one shared `let scaler = Scaler()` used by both lines
  // fails with "sending 'scaler' risks causing data races".
  async let a = Scaler().shrink(first)
  async let b = Scaler().shrink(second)
  return await (a, b)
}
```

## Sending a value that is not Sendable

A parameter or result marked `sending` moves a value to another domain, and the compiler
checks that the caller does not use the value again. Use `sending` when a function hands
a new class instance to its caller.

```swift
nonisolated final class Report {
  var lines: [String] = []
}

@concurrent
func buildReport(from rows: [String]) async -> sending Report {
  let report = Report()
  report.lines = rows.map { $0.uppercased() }
  return report
}
```

## Bridging a delegate you don't own

When a delegate protocol has no isolation and you know its methods are called on the
main thread, mark the method `nonisolated` and assert the isolation. The assertion traps
if the call arrives on another thread, and a trap is easier to find than a data race.

```swift
protocol LegacyPlayerDelegate: AnyObject {
  func playerDidFinish()
}

@MainActor
final class PlayerModel: LegacyPlayerDelegate {
  var isFinished = false

  nonisolated func playerDidFinish() {
    MainActor.assumeIsolated { isFinished = true }
  }
}
```

Use `@preconcurrency import Module` while a dependency has not adopted `Sendable`. The
compiler brings the warnings back when the dependency adopts it.

## Wrapping a callback in a continuation

Resume the continuation exactly once on every path, including the error path.
`resume(with:)` takes a `Result`, so one call covers success and failure. For a delegate
that calls back later, store the continuation and set the stored property to `nil` when
you resume.

```swift
func legacyFetch(_ completion: @escaping @Sendable (Result<Int, any Error>) -> Void) {
  completion(.success(42))
}

func fetch() async throws -> Int {
  try await withCheckedThrowingContinuation { continuation in
    legacyFetch { result in continuation.resume(with: result) }
  }
}
```

## Limiting a task group

The function below runs at most `limit` children at once. It starts `limit` children, and
it adds one more each time a child finishes.

```swift
func checksums(of files: [String], limit: Int = 4) async -> [String: Int] {
  await withTaskGroup(of: (String, Int).self) { group in
    var results: [String: Int] = [:]
    var pending = files.makeIterator()
    for _ in 0..<limit {
      guard let file = pending.next() else { break }
      group.addTask { (file, file.utf8.reduce(0) { $0 &+ Int($1) }) }
    }
    for await (file, sum) in group {
      results[file] = sum
      if let file = pending.next() {
        group.addTask { (file, file.utf8.reduce(0) { $0 &+ Int($1) }) }
      }
    }
    return results
  }
}
```

## Turning callbacks into an AsyncSequence

Create the source inside the `AsyncStream` closure, yield from the handler, and stop the
source in `onTermination`. The loop that reads the stream ends when the task is
cancelled.

```swift
nonisolated final class Ticker: Sendable {
  func start(_ onTick: @escaping @Sendable (Int) -> Void) { onTick(1) }
  func stop() {}
}

func ticks() -> AsyncStream<Int> {
  AsyncStream { continuation in
    let ticker = Ticker()
    ticker.start { continuation.yield($0) }
    continuation.onTermination = { _ in ticker.stop() }
  }
}
```

## Cancelling suspended work

`withTaskCancellationHandler` runs its handler at once when the task is cancelled, and
the handler runs at the same time as the body. State that both sides touch needs a
`Mutex` or an `Atomic`, because an actor cannot promise that the handler runs first.

```swift
import Synchronization

nonisolated final class Download: Sendable {
  private let cancelled = Atomic(false)
  func cancel() { cancelled.store(true, ordering: .relaxed) }
  func run() async -> Int { cancelled.load(ordering: .relaxed) ? 0 : 1 }
}

func fetch() async -> Int {
  let download = Download()
  return await withTaskCancellationHandler {
    await download.run()
  } onCancel: {
    download.cancel()
  }
}
```

## Task local values

A `@TaskLocal` value passes context such as a request ID to every child task without a
parameter on each function. Give it an optional type, so a read outside any binding has a
sensible result.

```swift
enum Trace {
  @TaskLocal static var requestID: String?
}

func handle() async {
  await Trace.$requestID.withValue("r-42") {
    await step()
  }
}

func step() async {
  print(Trace.requestID ?? "no request")
}
```

## Moving a target to Swift 6

Do the steps in order for one target, and then repeat for the next target. Start with
the app or UI target, because the SDK already isolates most of it to the main actor.

```text
1. Build with the new compiler in Swift 5 mode.
2. Turn on NonisolatedNonsendingByDefault and InferIsolatedConformances,
   or ApproachableConcurrency with Swift 6.4 tools, which includes both.
   For an app or UI target, also set the default isolation to MainActor.
3. Turn on complete concurrency checking, which reports Swift 6 errors as warnings.
4. Fix the warnings, and start with the fixes that clear the most lines:
   a var global that can be a let, a public struct that needs Sendable.
5. Switch the target to the Swift 6 language mode.
6. Refactor in a later change.
```

The settings for steps 2 and 3 in a package are below. In Xcode the build settings are
named "Approachable Concurrency", "Default Actor Isolation", and "Strict Concurrency
Checking".

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Shop",
  targets: [
    .target(
      name: "ShopUI",
      swiftSettings: [
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .defaultIsolation(MainActor.self),
        .enableExperimentalFeature("StrictConcurrency=complete"),
        .swiftLanguageMode(.v5),
      ]
    )
  ]
)
```

You can stop after any step and ship, because each fix is also correct in Swift 5 mode.
