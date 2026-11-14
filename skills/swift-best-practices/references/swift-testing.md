# Swift Testing (digest)

Source: https://developer.apple.com/documentation/testing . Read the digest when the user
asks for tests. Use Swift Testing for new tests. Keep XCTest for UI automation with
`XCUIApplication`, for performance tests with `XCTMetric`, and for tests written in
Objective-C. Both frameworks can live in one test target.

## From XCTest to Swift Testing

| XCTest | Swift Testing |
|---|---|
| `class FooTests: XCTestCase` | `struct FooTests`, or a function at file scope |
| `func testAdds()` | `@Test func adds()` |
| `setUp()` and `tearDown()` | `init` and `deinit`, and `deinit` needs a `class` or an `actor` |
| `XCTAssertEqual(a, b)`, `XCTAssertTrue(x)` | `#expect(a == b)`, `#expect(x)` |
| `XCTUnwrap(value)` | `try #require(value)` |
| `continueAfterFailure = false` | `try #require(...)` on the check that must hold |
| `XCTAssertThrowsError(try f())` | `#expect(throws: MyError.self) { try f() }` |
| `XCTSkip("reason")` | `.disabled("reason")` or `.enabled(if: condition)` |
| `XCTExpectFailure` | `withKnownIssue { }` |
| `expectation` and `wait(for:)` | `await confirmation { }`, or `await` the async function |
| A `for` loop over inputs | `@Test(arguments: inputs)` |

## A suite

A suite is a `struct`, and the library creates a new instance for each test, so stored
properties cannot leak from one test to the next. `#expect` records the values of both
sides when it fails. `#require` stops the test, and it also unwraps an optional.

```swift
import Testing

struct Cart {
  private(set) var items: [String: Int] = [:]
  mutating func add(_ name: String, count: Int = 1) { items[name, default: 0] += count }
  var total: Int { items.values.reduce(0, +) }
}

struct CartTests {
  var cart = Cart()

  @Test mutating func `adding an item twice sums the counts`() throws {
    cart.add("tea")
    cart.add("tea", count: 2)
    let count = try #require(cart.items["tea"])
    #expect(count == 3)
    #expect(cart.total == 3)
  }
}
```

## One test, many inputs

A parameterized test runs each argument as its own case, in parallel, and reports the
argument that failed. Two collections produce every combination, so wrap them in `zip`
when you want matched pairs.

```swift
import Testing

func isPalindrome(_ text: String) -> Bool {
  let letters = text.lowercased().filter(\.isLetter)
  return letters == String(letters.reversed())
}

@Test(arguments: zip(["Level", "A man, a plan", "swift"], [true, false, false]))
func palindromes(text: String, expected: Bool) {
  #expect(isPalindrome(text) == expected)
}
```

## Errors, known issues, and callbacks

```swift
import Testing

enum ParseError: Error, Equatable { case empty }

func parse(_ text: String) throws(ParseError) -> Int {
  guard let value = Int(text) else { throw .empty }
  return value
}

@Test func `empty input throws`() {
  #expect(throws: ParseError.empty) { try parse("") }
}

@Test func `rounding bug is tracked`() {
  withKnownIssue("rounds down, see issue 12") {
    #expect(Int(2.6) == 3)
  }
}

@Test func `handler runs twice`() async {
  await confirmation(expectedCount: 2) { called in
    for _ in 0..<2 { called() }
  }
}
```

`withKnownIssue` keeps the test compiling and running, and it reports when the issue
stops happening. A disabled test does neither, so prefer `withKnownIssue` for a failure
you expect to be fixed.

## Traits

| Trait | Use |
|---|---|
| `.enabled(if:)`, `.disabled("reason")` | run a test only under a condition |
| `.bug("https://example.com/issue/12")` | link a test to an issue |
| `.tags(.network)` | group tests across files, after you declare the tag in an `extension Tag` |
| `.timeLimit(.minutes(1))` | fail a test that runs too long |
| `.serialized` | run the cases of one suite one at a time |

Tests run in parallel and in random order. If a test fails only in parallel, it shares
state with another test, so remove the shared state and don't add `.serialized`. Use
`@available` on a test and not `#available` inside it, so the library can report the
test as skipped.

## Exit tests

An exit test runs its body in a child process, so you can test a `precondition` or a
`fatalError` path. Exit tests work on macOS, Linux, FreeBSD, and Windows. The body is not
on the main actor, so a function it calls from an app target with main actor default
isolation must be `nonisolated`.

```swift
import Testing

nonisolated func ratio(_ a: Int, _ b: Int) -> Int {
  precondition(b != 0, "divisor must not be zero")
  return a / b
}

@Test func `zero divisor traps`() async {
  await #expect(processExitsWith: .failure) {
    _ = ratio(1, 0)
  }
}
```

## What to test

Test behavior a caller can observe through the public API, and name each test for the
behavior. Test properties such as "encoding and then decoding returns the input". Don't
assert a constant against itself, and don't copy the implementation's branches into the
test.
