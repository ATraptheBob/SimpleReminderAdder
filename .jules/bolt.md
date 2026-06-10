## 2024-06-03 - Compiling Regular Expressions on Every Keystroke
**Learning:** `NSRegularExpression` initializers are computationally expensive in Swift. Constructing 16 of them repeatedly inside `parseRecurrence` during every text change (each keystroke) was causing unnecessary CPU overhead.
**Action:** Pre-compile static `NSRegularExpression` objects in properties so they are initialized exactly once and reused, achieving O(1) initialization cost instead of O(N).
## 2024-10-24 - Pre-compiling Regexes with dynamic properties
**Learning:** Even when regex patterns incorporate dynamic user properties (like list titles), initializing them repeatedly inside frequently invoked loops like `parseText()` during every keystroke causes significant performance lag due to regex compilation overhead.
**Action:** When a regex pattern depends on dynamic data (like lists), compile the regular expressions once whenever that backing data changes (e.g. `onChange` or during fetch) and cache the resulting `NSRegularExpression` objects in state or local variables to reuse across subsequent operations.
## 2024-10-25 - Caching NSDataDetector
**Learning:** `NSDataDetector` is a subclass of `NSRegularExpression` and its initialization is equally computationally expensive. Initializing it inside a frequently invoked function (like a parser running on every keystroke) creates a significant CPU overhead.
**Action:** Always cache instances of `NSDataDetector` as a thread-safe `static let` property if they are going to be used repeatedly.
