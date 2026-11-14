---
name: swift-best-practices
description: >-
  Write modern, correct, maintainable Swift. Use whenever you write, change, refactor,
  debug, or explain Swift code: structs, enums, classes, actors, protocols, generics,
  errors, async code, Sendable, SwiftUI views, Package.swift, or Swift tests. Trigger on
  Swift, SwiftUI, SwiftPM, Xcode, .swift files, a data race error, an actor isolation
  error, a hang, or a retain cycle, even when the user does not say "best practices".
---

# Swift best practices

The rules below describe Swift 6.4 in the Swift 6 language mode. Run `swift --version`
and read `swift-tools-version` in `Package.swift` before you use a feature, and use the
older form when the "Since" column in section 9 names a newer version than the project has.

## 1. Start with the simplest form

Swift lets you start with code that is simple, static, and single-threaded, and it lets
you add reference types, type erasure, concurrency, and unsafe code later. Use the left
column first, and move to the right column only when you can state the reason.

| Need | Start with | Move on when |
|---|---|---|
| Data | `struct` or `enum` | the value needs identity, sharing, or inheritance |
| Abstraction | a concrete type | two or more types repeat the same code |
| Polymorphism | `some P` or a generic | one collection must hold different types, so use `any P` |
| Execution | synchronous code on the main actor | a profile shows a hang, so use `async`, then `@concurrent`, then an `actor` |
| Memory | `Array` and `String` | a profile shows the cost, so use `InlineArray` or `Span` |
| Safety | the safe API | C interop needs a pointer, so use `unsafe` |

Library code and application code follow different rules. A library has users outside
its module, so it marks its public types `Sendable` on purpose, keeps its API
`nonisolated`, and documents every public declaration. An application keeps its types
`internal`, isolates them to the main actor, and adds no protocol or generic parameter
that only one type uses.

## 2. Checks to run before you hand back code

Run the checks below, and fix what they report.

```bash
swift build
swift test                                   # when the package has tests
swift format lint --strict --recursive Sources Tests
```

Fix a warning. Don't silence it with `@unchecked Sendable`, `nonisolated(unsafe)`,
`try!`, or `@preconcurrency`.

A target needs the settings below before the concurrency rules in section 5 are true.
Xcode calls the two upcoming features "Approachable Concurrency". With Swift 6.4 tools,
`.enableUpcomingFeature("ApproachableConcurrency")` turns on both, and
`swift package init` writes it for you.

```swift
// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .enableUpcomingFeature("InferIsolatedConformances"),
  .defaultIsolation(MainActor.self),  // app and UI targets only, never a library
]
// Pass `swiftSettings: settings` to each target, and set `swiftLanguageModes: [.v6]`.
```

If a project has no `.swift-format` file, suggest [`assets/swift-format.json`](../swift-review/assets/swift-format.json) from the
`swift-review` skill, saved as `.swift-format`, and the settings in `lints/Package.swift`
from https://github.com/bjoernaagaard/modern-swift.

## 3. Data

Use a `struct` or an `enum` for data, and declare a property with `let` unless code
mutates it. Use a `class` when the value has identity, such as a window or a database
connection, or when several owners must see the same changes.

Use one `enum` for states that exclude each other. Separate optional properties allow
combinations that should never happen, and code can update one property and forget
another.

```diff
 struct Upload {
-  var isUploading = false
-  var progress: Double?
-  var error: (any Error)?
-  var resultURL: URL?
+  enum State {
+    case idle
+    case uploading(progress: Double)
+    case failed(any Error)
+    case finished(URL)
+  }
+  var state = State.idle
 }
```

A struct that stores a mutable class instance does not have value semantics, because two
copies of the struct share one object. Keep the stored class instance private and never
mutate it, or copy it before each write. [`references/performance-and-arc.md`](references/performance-and-arc.md) shows the
copy before a write.

Use a noncopyable type, written `~Copyable`, for a resource that must have one owner.
Mark the method that ends its life `consuming`, and the compiler rejects any later use.

```swift
struct Transfer: ~Copyable {
  let amount: Int
  consuming func commit() { print("sent", amount) }
}

func pay() {
  let transfer = Transfer(amount: 10)
  transfer.commit()
  // transfer.commit()  // error: 'transfer' consumed more than once
}
```

## 4. Errors and optionals

Choose the mechanism from what the caller can do about the failure.

| Situation | Use |
|---|---|
| Absence is a normal result, e.g., `first` or a dictionary lookup | `Optional` |
| The caller may need to know what failed | `throws` |
| The code itself is wrong, e.g., an index out of bounds | `precondition` or `fatalError` with a message |

Make an error an `enum` whose cases carry the values that failed, and conform it to
`LocalizedError` or `CustomStringConvertible` when a person will read it. Use `guard` for
a condition that must exit, because the compiler forces the `else` branch to leave.

```swift
enum ConfigError: Error, Equatable {
  case missingKey(String)
  case notANumber(key: String, value: String)
}

func port(in settings: [String: String]) throws(ConfigError) -> Int {
  guard let text = settings["port"] else { throw .missingKey("port") }
  guard let port = Int(text) else { throw .notANumber(key: "port", value: text) }
  return port
}
```

Write typed throws, `throws(ConfigError)`, on internal functions and on generic code
that forwards an error. Write plain `throws` on a library's public API, so the library
can add an error type later without breaking callers.

Don't write `!`, `try!`, or an implicitly unwrapped `T!` on a path that outside input
can reach. Don't write `try?`, or a `catch` that only logs, when the caller needs the
reason, because both discard the error. When an invariant makes `nil` impossible, state
the invariant in the message.

Trust the types. Make a property optional only when it can be `nil`, and don't check or
catch what the compiler already rules out. Validate outside input once, where it enters.

```diff
-let url = URL(string: "https://example.com/api")!
+guard let url = URL(string: "https://example.com/api") else {
+  preconditionFailure("the API address is a constant and must parse")
+}
```

## 5. Concurrency

Add concurrency in the order below, and stop at the first step that fixes the problem.

```text
1. synchronous code on the main actor     enough for most app code
2. async and await                        a call waits on the network or the disk
3. @concurrent on your own function       Instruments shows your code hangs the main thread
4. an actor                               state must live off the main actor
```

With the settings from section 2, the annotation on a function decides where it runs.
Without `NonisolatedNonsendingByDefault`, a plain `nonisolated async` function switches
to the global concurrent pool, so check the setting before you reason about a hang.

| Declaration | Where it runs |
|---|---|
| `func load() async` on a main actor type | on the main actor |
| `nonisolated func load() async` | on the caller's actor |
| `@concurrent func load() async` | on the global concurrent pool |

A library writes `nonisolated`, and the caller decides where the work runs. Your own
slow function writes `@concurrent`.

```swift
struct Photo: Sendable {
  var thumbnail: [UInt8]
  var colors: [UInt8]
}

nonisolated struct PhotoDecoder {
  @concurrent
  func photo(from data: [UInt8]) async -> Photo {
    async let thumbnail = shrink(data)
    async let colors = dominantColors(data)
    return await Photo(thumbnail: thumbnail, colors: colors)
  }

  @concurrent
  private func shrink(_ data: [UInt8]) async -> [UInt8] { Array(data.prefix(64)) }

  @concurrent
  private func dominantColors(_ data: [UInt8]) async -> [UInt8] { Array(data.suffix(3)) }
}
```

Other code can run on an actor at every `await`, so state can change while a function
is suspended. Change actor state in synchronous methods, and check the state again after
each `await`. The cache below stores the running task before it suspends, so two callers
for one address share one download.

```swift
actor ImageCache {
  private var finished: [String: [UInt8]] = [:]
  private var running: [String: Task<[UInt8], Never>] = [:]

  func image(for address: String) async -> [UInt8] {
    if let bytes = finished[address] { return bytes }
    if let task = running[address] { return await task.value }
    let task = Task { await download(address) }
    running[address] = task
    let bytes = await task.value
    finished[address] = bytes
    running[address] = nil
    return bytes
  }

  private func download(_ address: String) async -> [UInt8] { Array(address.utf8) }
}
```

An actor runs high priority work first, so it does not keep the order of calls. Use one
task or an `AsyncStream` when order is required. Never hold a lock across an `await`, and
never block a thread with `DispatchSemaphore` to wait for async work.

### Sendable and data race errors

A `Sendable` type is safe to use from two isolation domains at once. The compiler infers
`Sendable` for an internal struct or enum whose stored properties are `Sendable`, and you
must write it yourself on a public type. Leave a model class non-`Sendable` and keep it
on one actor. A non-`Sendable` value can still move to another actor when the sender
stops using it.

When the compiler reports a data race, try the fixes in the order below.

```text
1. Stop sharing.       Give each task its own copy or its own instance.
2. Make it a value.    A Sendable struct or enum is copied, not shared.
3. Isolate it.         Put it on the main actor or on your own actor.
4. Lock it.            Store a Mutex or Atomic from Synchronization in a let property.
5. Promise by hand.    @unchecked Sendable, only on a type that has its own lock.
```

Fix a mutable global or static in the same way. Make it a `let` if you can, then put it
on `@MainActor`, then wrap it in a `Mutex`. Use `nonisolated(unsafe)` last, and write a
comment that says what protects the value.

## 6. Structured tasks

Prefer a structured task. A structured task ends before its scope ends, and it inherits
cancellation, priority, and task local values from its parent.

| Need | Use |
|---|---|
| A fixed number of concurrent jobs | `async let` |
| A number of jobs known at run time | `withTaskGroup`, with a limit on running children |
| Children that return nothing | `withDiscardingTaskGroup` |
| Work started by a button or a delegate callback | `Task { }`, and keep the handle so you can cancel it |
| A task that inherits nothing | `Task.detached`, which you should almost never need |

Don't start one child per element of a long list. Start a fixed number of children, and
add one each time a child finishes. [`references/concurrency.md`](references/concurrency.md) has the full pattern.

Cancellation only sets a flag. Call `try Task.checkCancellation()` before each expensive
step, and use `withTaskCancellationHandler` for work that is suspended inside a callback
API. Wrap a write that must finish in `withTaskCancellationShield` (Swift 6.4).

A continuation must resume exactly once on every path. If it never resumes, the caller
waits forever, and a second resume traps. [`references/concurrency.md`](references/concurrency.md) shows how to wrap
a callback API.

## 7. Protocols and generics

Write concrete types first. Add a protocol when two types repeat the same code and each
type needs its own implementation of some operation. If every conforming type would use
the same implementation, write an extension on an existing protocol and add no new
protocol. Prefer a struct that stores another value over a class that inherits from one.
Add no wrapper type or function that only forwards calls.

| Write | Meaning | Use when |
|---|---|---|
| `some P` | one concrete type, known to the compiler | by default, for parameters and results |
| `any P` | a box that can hold any conforming type | a collection or property must hold different types |
| `some Collection<Int>` | hides the type and keeps the element type | a result type is long or private |

You cannot call a method on `any P` when the method takes an associated type. Pass the
value to a function that takes `some P`, and the compiler opens the box for that call.

A protocol requirement is dispatched at run time, so the conforming type's method runs.
A method that exists only in a protocol extension is chosen at compile time, so code that
holds `any P` calls the extension's method even when the type has its own.

```swift
protocol Greeter {
  func greet() -> String  // requirement: a conforming type can replace it
}

extension Greeter {
  func greet() -> String { "hello" }
  func shout() -> String { "HELLO" }  // extension only: a conforming type cannot replace it
}

struct Pirate: Greeter {
  func greet() -> String { "ahoy" }
  func shout() -> String { "AHOY" }
}

func demo() {
  let greeter: any Greeter = Pirate()
  print(greeter.greet())  // ahoy
  print(greeter.shout())  // HELLO
}
```

A forced downcast, `as!`, usually means a class hierarchy or an `any P` lost a type that
a generic parameter would have kept.

## 8. API design

A call should read clearly at the place where it is used. The rules come from the Swift
API Design Guidelines, and [`references/api-design-guidelines.md`](references/api-design-guidelines.md) has the full list.

| Rule | Write | Not |
|---|---|---|
| Name a method without side effects as a noun phrase | `list.sorted()`, `x.distance(to: y)` | `list.getSorted()` |
| Name a method with side effects as a verb | `list.sort()`, `list.append(x)` | `list.sorting()` |
| Name a Boolean as an assertion | `isEmpty`, `hasSuffix(_:)` | `empty`, `checkSuffix` |
| Leave out words that repeat the type | `remove(member)` | `removeElement(member)` |
| Label an argument so the call reads as a phrase | `move(to: point)` | `move(point)` |
| Add no type prefix | `Parser` | `XYZParser` |
| Add no `get` prefix | `posts()` | `getPosts()` |
| Use the domain word, not a vague one | `photo(from:)`, `ThumbnailCache` | `process(_:)`, `handleData()`, `ImageManager` |

Write the narrowest access level that works. Use `private`, then `internal`, then
`package`, then `public`. Every `public` declaration is a promise to callers, so give it
a `///` comment whose first line is a one sentence summary, and say what it throws. A
comment says why, not what. A trivial member needs only the summary line.

Replace a `Bool` parameter in a public function with a two case `enum` when the call
site does not explain it, e.g., `render(.draft)` and not `render(true)`. Use a dedicated
type such as `UUID`, `URL`, or `Duration` and not a `String` or a number.

## 9. Old form and new form

Agents often write the form in the left column, so check new code against the table.
"Since" is the Swift version that added the form in the right column.

| Old form | New form | Since |
|---|---|---|
| A nested ternary, or a closure called at once to set a `let` | `if` and `switch` expressions | 5.9 |
| `ObservableObject` with `@Published` | `@Observable` | 5.9 |
| `any Error` everywhere in internal code | `throws(MyError)` | 6.0 |
| `XCTestCase` and `XCTAssertEqual` | `@Test` and `#expect` from Swift Testing | 6.0 |
| A class with a lock, or a serial `DispatchQueue` | `Mutex` from `Synchronization`, or an `actor` | 6.0 |
| `DispatchQueue.global().async`, `Task.detached` | `@concurrent func` | 6.2 |
| `withUnsafeBufferPointer` | `array.span`, and `data.bytes` for raw bytes | 6.2 |
| `Array` of a fixed size in a hot path | `InlineArray<N, T>` | 6.2 |
| Observing changes with Combine or polling | `Observations { }` | 6.2 |
| `Process` with pipes | the Subprocess package | 6.2 |
| `Rocket.SaturnV` when a type hides a module name | `Rocket::SaturnV` | 6.3 |
| `@_cdecl` | `@c` | 6.3 |
| `@available(iOS 26, macOS 26, tvOS 26, *)` | `@available(anyAppleOS 26, *)` | 6.4 |
| `@unchecked Sendable` because of a `weak var` | `weak let` | 6.4 |
| Checking `Task.isCancelled` to finish a write | `withTaskCancellationShield` | 6.4 |
| Warnings as errors for a whole module | `@diagnose(Group, as: error)` on one declaration | 6.4 |

Use `Logger` from `os` in app code and not `print`, and use Swift Regex and Foundation's
`FormatStyle` parsers and not index arithmetic on a `String`.

## 10. Changing existing code

Keep the public behavior the same unless the user asked you to change it. First, list
what the code does now, including the order of results and what happens on empty input.
Second, make the change the user asked for and fix each problem they named. Third, show
the before and after of every signature that changed, and give the reason.

Keep one form across a group of related types, e.g., every view model is either
`ObservableObject` or `@Observable`. Move the whole group to the new form from section 9,
or leave the group alone and tell the user.

Keep odd behavior you don't understand, and tell the user about it. Don't turn on Swift
6 checking and refactor in the same change, and read [`references/concurrency.md`](references/concurrency.md) first
when the task is a migration.

## 11. Final checklist

Before you return Swift code, confirm each line.

- `swift build` and `swift format lint --strict` report nothing, and tests pass if the
  package has tests.
- No `!`, `try!`, or `as!` sits on a path that outside input can reach, and each
  `precondition` has a message.
- No `@unchecked Sendable`, `nonisolated(unsafe)`, or `Task.detached` appears without a
  comment that gives the reason.
- No `await` sits between a check of actor state and the write that depends on the check.
- Data is a `struct` or `enum`, and each `class` has a stated reason.
- Parameters and results use `some P` or a generic, and `any P` appears only where
  different types are stored together.
- Every `public` declaration has a doc comment, and a public value type that is safe to
  share is marked `Sendable`.
- No form from the left column of section 9 remains, and no group of related types mixes
  an old form with its new form.

## 12. References

Read a reference when its case comes up.

- [`references/api-design-guidelines.md`](references/api-design-guidelines.md): you are naming or documenting a public API.
- [`references/concurrency.md`](references/concurrency.md): a data race or isolation error does not yield to section
  5, you are wrapping a callback or delegate API, you need a task group with a limit, or
  you are moving a target to Swift 6.
- [`references/swift-testing.md`](references/swift-testing.md): the user asked for tests.
- [`references/swiftui.md`](references/swiftui.md): the target imports SwiftUI.
- [`references/performance-and-arc.md`](references/performance-and-arc.md): a profile shows a cost, a struct needs to copy
  its storage before a write, or a retain cycle needs fixing.
- [`references/unsafe-and-interop.md`](references/unsafe-and-interop.md): the code calls C, C++, or Objective-C, or uses a
  pointer.
- [`references/macros.md`](references/macros.md): you are writing or testing a macro.
- [`references/logging.md`](references/logging.md): you are adding logs or diagnostics.
- [`references/google-swift-style.md`](references/google-swift-style.md): a formatting or file layout question that
  `swift format` does not settle.
