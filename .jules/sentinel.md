
## 2024-05-30 - [Regex Injection via \Q...\E block in Swift]
**Vulnerability:** A regex injection vulnerability was found in `QuickAddView.swift` where a Reminders list title (user input) was placed directly inside a regex literal block: `\\Q\(list.title)\\E`. If the list title contained `\\E`, it would prematurely end the literal block and allow arbitrary regex characters to be interpreted, potentially leading to catastrophic backtracking (ReDoS) or application crashes.
**Learning:** Using `\Q...\E` is unsafe if the inner string can contain `\E`.
**Prevention:** Always use `NSRegularExpression.escapedPattern(for: string)` to sanitize user input before embedding it into a regular expression.

## 2024-06-10 - [Missing Input Length Limits Leading to ReDoS]
**Vulnerability:** The application was passing unbounded text inputs (`taskText`) directly to the `NaturalDateParser`, which evaluated the text against over 30 pre-compiled regular expressions on every keystroke. Extremely long inputs could cause severe CPU exhaustion or Regular Expression Denial of Service (ReDoS).
**Learning:** Even with pre-compiled and escaped regular expressions, unbounded inputs can exponentially increase parsing time and hog the main thread, leading to an unresponsive application.
**Prevention:** Implement strict length limits on any user input field that triggers regular expression evaluations, especially those happening in real-time (e.g., `onChange`).

## 2024-06-11 - [Input Validation for EKReminder titles]
**Vulnerability:** The application was allowing arbitrary control and formatting characters (`\p{Cc}`) to be saved into the `EKReminder` titles. This can lead to UI spoofing (e.g., using Right-to-Left Overrides) or unexpected application behavior when these characters are rendered in standard system UIs like the Reminders app.
**Learning:** Even when inputs are constrained in length, their content must be sanitized for control characters to ensure safe rendering.
**Prevention:** Apply a regular expression replacement (e.g. `replacingOccurrences(of: "\\p{Cc}", with: "", options: .regularExpression)`) to strip potentially malicious invisible characters before persisting user text.
