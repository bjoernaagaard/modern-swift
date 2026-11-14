<img src="assets/icon.svg" width="64" height="64" alt="">

# modern-swift

modern-swift is a set of three agent skills for writing, reviewing, and porting Swift.
The rules describe Swift 6.4 in the Swift 6 language mode. The repository also holds
lint settings for the rules a tool can check, and graded tasks that measure whether an
agent follows each skill.

## Install

```bash
npx skills add bjoernaagaard/modern-swift
```

## The skills

| Skill | The agent uses it when you ask it to | It produces |
|---|---|---|
| `swift-best-practices` | write, change, refactor, or debug Swift | Swift code that passes `swift build` and `swift format lint` |
| `swift-review` | review, audit, or check Swift | a report with ranked findings, and no code changes |
| `swift-port` | port TypeScript, JavaScript, Python, or Kotlin to Swift | a Swift package, ported tests, and `PORTING.md` |

`swift-review` and `swift-port` apply the rules in `swift-best-practices`, so install all
three together.

## How swift-best-practices is organized

The skill tells the agent to start with the simplest form and to move on only for a
stated reason.

| Need | Start with | Move on when |
|---|---|---|
| Data | `struct` or `enum` | the value needs identity, sharing, or inheritance |
| Polymorphism | `some P` or a generic | one collection must hold different types |
| Execution | synchronous code on the main actor | a profile shows a hang |
| Safety | the safe API | C interop needs a pointer |

`SKILL.md` holds the rules that every task needs. A reference file holds the rules for
one kind of task, and the agent reads it only when that kind of task comes up.

```text
skills/swift-best-practices/
├── SKILL.md                        # data, errors, concurrency, generics, API design
└── references/
    ├── api-design-guidelines.md    # naming or documenting a public API
    ├── concurrency.md              # isolation errors, callbacks, moving to Swift 6
    ├── swift-testing.md            # the user asked for tests
    ├── swiftui.md                  # the target imports SwiftUI
    ├── performance-and-arc.md      # a profile shows a cost, or a retain cycle
    ├── unsafe-and-interop.md       # C interop or pointers
    ├── macros.md                   # writing a macro
    ├── logging.md                  # adding logs
    └── google-swift-style.md       # formatting questions
```

Most rules come with a code example, and each `swift` example in the skills compiles on
Swift 6.4.2 without warnings. For example, the skill shows the rule "use one enum for
states that exclude each other" as a change to a struct.

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

## How swift-review works

```text
review(target)
  1. decide the scope        file, package, or diff; library or app; Swift version
  2. run the tools           swift build, swift format lint, swift test
  3. read for problems       correctness, errors, API design, idiom, docs
  4. write the report        Must fix, Should fix, Consider, What is already good
  5. offer the lint settings
```

Each finding gives a `file:line` location, the rule and its source, and the fix as a
short change.

```markdown
### 1. The continuation never resumes on failure (`Sources/Feed/FeedView.swift:50`)

**Rule:** A continuation must resume exactly once on every path (swift-best-practices, section 6)
**Problem:** When the request fails, `data` is `nil` and nothing resumes, so the spinner never stops.
**Fix:** resume with the error in an `else` branch.
```

## How swift-port works

```text
port(source)
  1. list the original's observable behavior
  2. port the tests to Swift Testing
  3. design the Swift API, then implement it
  4. keep the port in proportion to the original
  5. run swift build and swift test
  6. write PORTING.md
```

The skill has a mapping table for each source language. Some rows are below.

| In the original | In Swift |
|---|---|
| TypeScript union of string literals | `enum` with `String` raw values |
| TypeScript `Promise.all` | `async let`, or a task group |
| Python exception hierarchy | one error `enum` with associated values |
| Python `dict` in insertion order | an array of pairs, because `Dictionary` has no stable order |
| Kotlin `sealed class` | `enum` with associated values |

## Lint settings

`lints/` holds the compiler settings and the `swift format` rules that report the rules
a tool can check. Copy the `settings` array from `lints/Package.swift` into your own
`Package.swift`, and copy `lints/.swift-format` to the root of your project. The
`swift-review` skill ships the same file as [`assets/swift-format.json`](skills/swift-review/assets/swift-format.json), so an installed
skill always has it.

```text
lints/
├── Package.swift     # upcoming features, strict memory safety, default isolation
├── .swift-format     # a link to skills/swift-review/assets/swift-format.json
└── check/            # one Swift file for each rule, written to trigger its warning
```

To confirm that each setting still reports its rule, run the two commands below. Each
file in `check/` names the warning it expects in its first line.

```bash
cd lints
swift build
swift format lint --recursive check
```

## Evals

An eval is a task for an agent, with one grader file for each behavior the result should
show. The format matches the evals in
[BeautifulRust](https://github.com/morganlinton/BeautifulRust).

```text
skills/<skill>/evals/<case>/
├── case.yaml         # the name and the expected outcome
├── prompt.md         # what the user asks
├── files/            # the starting files, if the task has any
├── place-files.sh    # copies files/ into the working folder
└── graders/          # one file per expected behavior
```

| Skill | Eval | The task |
|---|---|---|
| `swift-best-practices` | `log-summary-cli` | write a command line tool that must not crash on bad input |
| `swift-best-practices` | `refactor-inventory-module` | remove planted problems and keep the behavior |
| `swift-best-practices` | `photo-pipeline-concurrency` | move slow work off the main actor without unsafe shortcuts |
| `swift-review` | `review-inventory-module` | find the planted problems and leave the code unchanged |
| `swift-review` | `review-swiftui-feed` | find the concurrency faults and accept SwiftUI conventions |
| `swift-port` | `port-python-task-graph` | port a Python module and its 12 tests |
| `swift-port` | `port-typescript-cart-pricing` | port a TypeScript module and its 26 tests |

The repository has no script that runs the evals. Use a runner that reads the
BeautifulRust format.

## Sources

The rules draw on the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/),
the [Swift 6 migration guide](https://www.swift.org/migration/), the
[Swift Testing documentation](https://developer.apple.com/documentation/testing), and the
[Google Swift Style Guide](https://google.github.io/swift/). The layout of the skills and
the evals follows BeautifulRust.

## License

The repository is under the MIT license, which is in `LICENSE`.
