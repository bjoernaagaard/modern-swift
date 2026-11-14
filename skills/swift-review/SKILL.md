---
name: swift-review
description: >-
  Review existing Swift code for correctness, data race safety, error handling, API
  design, and maintainability, and write a prioritized report where every finding cites
  the rule it breaks and shows the fix. Use for a review, audit, critique, grade, or check
  of a .swift file, a package, a target, a diff, or a pull request, or when the user asks
  what is wrong with their Swift or how to make it more modern, even if they don't say
  "review".
---

# Swift review

Review Swift code against the rules the `swift-best-practices` skill uses for writing it,
and report what to change. The output is a report, and the reader decides what to fix.
Rewrite code only when the user asks for a rewrite.

```text
review(target)
  1. decide the scope
  2. run the tools, if they are available
  3. read for problems, in priority order
  4. write the report
  5. offer the lint settings
```

## 1. Decide the scope

Settle the four facts below before you read for problems, and state your assumptions in
the first paragraph of the report.

| Fact | Where to find it | Why it changes the review |
|---|---|---|
| What to read | the file, target, or diff the user named | for a diff, review the changed lines and the code they break, not the whole file |
| Library or application | `public` declarations, a `.library` product in `Package.swift` | a library is held to the API rules, and an application is held to the simplicity rules |
| Swift version and settings | `swift-tools-version`, `swiftLanguageModes`, `swiftSettings`, or the Xcode build settings | don't recommend a feature the project cannot use |
| Frameworks | the `import` lines | for SwiftUI code, read `references/swiftui.md` in `swift-best-practices` first |

The concurrency settings change what the code does. Without the upcoming feature
`NonisolatedNonsendingByDefault`, a `nonisolated async` function runs on the global
concurrent pool. With the feature, the function runs on the caller's actor. The upcoming
feature `ApproachableConcurrency` includes it. Find out which applies before you report
a hang or a data race.

## 2. Run the tools first, if you can

Run the commands below from the package root, and fold the results into the report. The
tools find the mechanical problems, so you can spend your attention on design.

```bash
swift build 2>&1 | grep -E "warning|error"
swift format lint --recursive Sources Tests
swift test
```

Don't paste raw tool output. Group repeated warnings into one finding, and leave out
formatting warnings that `swift format` can fix by itself. If a tool is not available or
the project does not build, say so in the report and review by reading.

## 3. What to look for, in priority order

Work through the groups in order. Most bugs are in the first two groups.

### Correctness and data race safety

| Look for | Consequence |
|---|---|
| `@unchecked Sendable` on a type with no lock, or `nonisolated(unsafe)` on a mutable global | a data race the compiler can no longer report |
| An `await` between a check of actor state and the write that depends on the check | two callers both pass the check, and one write is lost or the work runs twice |
| A continuation that some path never resumes, or that two paths resume | the caller waits forever, or the program traps |
| `DispatchSemaphore.wait`, `Thread.sleep`, or a lock held across an `await` | a blocked thread in the concurrent pool, and a possible deadlock |
| `!`, `try!`, `as!`, an array index, or integer arithmetic that outside input can reach | a crash on bad input |
| A closure stored on an object that captures the object strongly | a retain cycle, so neither object is freed |
| A struct that stores a mutable class instance and exposes it | two copies of the struct change each other |
| `Task { }` whose handle is dropped while the work should stop with its owner | work that continues after the screen or object is gone |
| A hand written `==` that disagrees with `hash(into:)` or with `<` | wrong results from `Set`, `Dictionary`, and `sort` |
| A `weak` reference unwrapped with `if let` where `nil` means a bug | a silent wrong result in place of a crash you could find |

### Error handling

- `try?`, an empty `catch`, or a `catch` that only logs discards an error the caller or
  the user needs.
- An error type is a `String`, an `NSError` built by hand, or an enum case with no
  associated value, so the message cannot say which file, key, or value failed.
- `fatalError` or `precondition` reports a failure that outside input can cause, e.g., a
  missing file or a bad response.
- A library's public function uses typed throws, so the library cannot add an error type
  later without breaking callers.
- `Task.isCancelled` is never checked in a long loop, or a `catch` treats
  `CancellationError` as a failure and shows it to the user.

### API design, applied strictly to a library

- Types: a `class` that has no identity, sharing, or inheritance, or a set of optional
  properties and Boolean flags that should be one `enum`.
- Abstraction: a protocol with one conforming type, a wrapper that only forwards calls, a
  class hierarchy where composition works, or `any P` where `some P` or a generic keeps
  the type.
- Naming: a `get` prefix, a type prefix, a name that repeats the type, a vague name such
  as `process`, `handle`, or `Manager` where a domain word exists, a mutating and
  nonmutating pair that does not follow the `sort` and `sorted` pattern, or a `Bool`
  parameter that the call site does not explain.
- Visibility: `public` on a declaration no other module uses, a public stored property
  that should have a `private(set)`, or a public value type that is safe to share but is
  not marked `Sendable`.
- Isolation: `@MainActor` or `@concurrent` on a general purpose library API, which
  should be `nonisolated` so the caller chooses where it runs.

### Idiom and clarity

- A form from the left column of the "Old form and new form" table in
  `swift-best-practices`, e.g., `ObservableObject`, `DispatchQueue.global().async`, a
  completion handler next to available async APIs, or `XCTAssertEqual` in a new test.
  Report one finding when a group of related types mixes an old form with its new form.
- Defensive code the types already rule out, e.g., an optional property that is never
  `nil`, a `guard` on a value that cannot fail, or a `do` and `catch` around code that
  cannot throw.
- An `async` function with no `await`. Skip a `@concurrent` function, which must be
  `async` to leave the caller's actor.
- `Task.detached`, or `Task { }` where `async let` or a task group fits the scope.
- A task group that starts one child for each element of a list with no limit.
- `remove(at:)` or `contains` in a loop over the same array, or a chain of `map` and
  `filter` in code a profile shows is slow.
- `print` for diagnostics in an app, or a log line that marks personal data
  `privacy: .public`.
- Nested `if let` where `guard` would keep the main path unindented.

### Documentation and tests

- A public declaration has no `///` comment, or a comment repeats the name or the code.
- A function that throws does not say what it throws, or a function with a
  `precondition` does not state the precondition.
- Logic has no tests, a test asserts a constant against itself, or a test is commented
  out when `.disabled` or `withKnownIssue` would keep it compiling.

The `swift-best-practices` skill and its `references/` folder hold the full rules and
their reasons. If the skill is installed, read the relevant reference when a finding
needs a rule you are unsure of.

## 4. Write the report

Copy the structure of `assets/review-template.md`, and sort the findings into its three
groups.

| Group | A finding belongs here when |
|---|---|
| Must fix | it is a bug, a data race, a crash that input can reach, a leak, or an API mistake that becomes a breaking change after release |
| Should fix | the code works but breaks a rule with a cost, e.g., an error with no context, code that is hard to test, or a confusing API |
| Consider | it concerns style, naming, or an old form that still works |

Each finding follows the rules below.

- Cite a location as `file:line`, or write `whole file` when there is no single line.
  Cite the rule and its source so the reader can look it up. Sources are the Swift API
  Design Guidelines, a Swift Evolution proposal number such as SE-0461, a compiler
  diagnostic group such as `#RegionIsolation`, a `swift format` rule name such as
  `NeverForceUnwrap`, or a section of `swift-best-practices`.
- Show the fix as code, and keep it to the lines that change. A `diff` block is the
  clearest form for a change of one to five lines.
- Group repeats. Write one finding for "six force unwraps on parsed values" and list the
  lines.
- Respect intent. When a comment explains an odd choice, put the finding under Consider
  and state the tradeoff.
- Keep the report in proportion to the code. Five to ten findings are enough for a short
  file. Don't pad the list, and don't place a bug among style comments.
- Don't report a framework convention as a problem. For example, a SwiftUI view is a
  struct with `@State private var` properties, and a view needs no `@MainActor`.
- Always fill in "What is already good" with two to four specific points, so the author
  knows what to keep.

## 5. Offer the lint settings

If the project has no `.swift-format` file, or its targets lack the settings from
section 2 of `swift-best-practices`, end the report by suggesting `assets/swift-format.json`
from this skill, saved as `.swift-format`, and `lints/Package.swift` from
https://github.com/bjoernaagaard/modern-swift. Name two or three findings from the review that
the settings would have reported.
