---
type: llm
focus: trace
weight: 1
---

REVIEW.md flags that formattedName is async but never awaits, and does not report resizeAvatar for the same reason, since a @concurrent function must be async
