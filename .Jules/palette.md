## 2024-10-27 - Icon-only buttons lacking context
**Learning:** Found an icon-only checkmark button in SearchResultsStripView that lacked accessibility labels or tooltips, meaning screen readers and pointer users wouldn't understand its function.
**Action:** Added `.accessibilityLabel` and `.help` modifiers with dynamic text based on the item's completion state to improve usability and accessibility.

## 2026-06-10 - Contextless interactive chips
**Learning:** Found that the dynamic tags/chips in `ChipsView` (like Priority, List, etc.) relied purely on visual layout and icons for context. A screen reader reading "Medium" or "Groceries" lacks the context that these are a Priority level or a List name. Additionally, the interactive priority chip lacked button traits.
**Action:** Applied `.accessibilityElement(children: .ignore)` and a combined `.accessibilityLabel` to all chips to announce both their category and value. Added `.accessibilityAddTraits(.isButton)` and an `.accessibilityHint` to the expandable priority chip.
