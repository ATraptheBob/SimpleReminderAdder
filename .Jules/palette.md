## 2024-10-27 - Icon-only buttons lacking context
**Learning:** Found an icon-only checkmark button in SearchResultsStripView that lacked accessibility labels or tooltips, meaning screen readers and pointer users wouldn't understand its function.
**Action:** Added `.accessibilityLabel` and `.help` modifiers with dynamic text based on the item's completion state to improve usability and accessibility.
