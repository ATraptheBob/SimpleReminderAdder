## 2024-06-03 - Compiling Regular Expressions on Every Keystroke
**Learning:** `NSRegularExpression` initializers are computationally expensive in Swift. Constructing 16 of them repeatedly inside `parseRecurrence` during every text change (each keystroke) was causing unnecessary CPU overhead.
**Action:** Pre-compile static `NSRegularExpression` objects in properties so they are initialized exactly once and reused, achieving O(1) initialization cost instead of O(N).
