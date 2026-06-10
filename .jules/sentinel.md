
## 2024-05-30 - [Regex Injection via \Q...\E block in Swift]
**Vulnerability:** A regex injection vulnerability was found in `QuickAddView.swift` where a Reminders list title (user input) was placed directly inside a regex literal block: `\\Q\(list.title)\\E`. If the list title contained `\\E`, it would prematurely end the literal block and allow arbitrary regex characters to be interpreted, potentially leading to catastrophic backtracking (ReDoS) or application crashes.
**Learning:** Using `\Q...\E` is unsafe if the inner string can contain `\E`.
**Prevention:** Always use `NSRegularExpression.escapedPattern(for: string)` to sanitize user input before embedding it into a regular expression.
