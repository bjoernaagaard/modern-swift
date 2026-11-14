# Swift review: [target]

[One paragraph: what the code does, whether it is a library or an application, the Swift
version and concurrency settings you assumed, which tools you ran, the verdict, and the
most important fix.]

## Must fix

### 1. [Short title] (`Sources/Module/File.swift:line`)

**Rule:** [rule and source, e.g., `NeverForceUnwrap` or "`swift-best-practices` 4. Errors and optionals"]
**Problem:** [what is wrong and its consequence, in one or two sentences]
**Fix:** [code for only the lines that change, never prose alone]

```diff
-old line
+new line
```

## Should fix

### 2. [Short title] (`Sources/Module/File.swift:line`)

**Rule:** [rule and source, e.g., `NeverForceUnwrap` or "`swift-best-practices` 4. Errors and optionals"]
**Problem:** [consequence]
**Fix:** [code for only the lines that change, never prose alone]

```diff
-old line
+new line
```

## Consider

### 3. [Short title] (`Sources/Module/File.swift:line`)

**Rule:** [rule and source, e.g., `NeverForceUnwrap` or "`swift-best-practices` 4. Errors and optionals"]
**Problem:** [why the change would help, and the tradeoff]
**Fix:** [short change]

## What is already good

- [Specific behavior or design to keep]
- [Second specific behavior or design to keep]

## Suggested settings

[Only when the project lacks them: the settings to add, and the findings above that the
settings would have reported.]
