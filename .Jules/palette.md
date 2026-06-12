## 2024-10-27 - Icon-only buttons lacking context
**Learning:** Found an icon-only checkmark button in SearchResultsStripView that lacked accessibility labels or tooltips, meaning screen readers and pointer users wouldn't understand its function.
**Action:** Added `.accessibilityLabel` and `.help` modifiers with dynamic text based on the item's completion state to improve usability and accessibility.

## 2026-06-10 - Contextless interactive chips
**Learning:** Found that the dynamic tags/chips in `ChipsView` (like Priority, List, etc.) relied purely on visual layout and icons for context. A screen reader reading "Medium" or "Groceries" lacks the context that these are a Priority level or a List name. Additionally, the interactive priority chip lacked button traits.
**Action:** Applied `.accessibilityElement(children: .ignore)` and a combined `.accessibilityLabel` to all chips to announce both their category and value. Added `.accessibilityAddTraits(.isButton)` and an `.accessibilityHint` to the expandable priority chip.

## 2026-11-20 - Invisible interactive components
**Learning:** Found that the hotkey recorder in SettingsView and dictation trigger relied on visual context or keyboard shortcuts alone. Screen readers would encounter them as static text or unlabeled actions, leaving users confused about how to interact with the recording state.
**Action:** Always provide `.accessibilityLabel`, dynamic `.accessibilityValue`, and `.accessibilityHint` for custom interactive state buttons, and ensure icon-only buttons (like a Dictation Mic) have explicit labels.

## 2024-12-07 - Contextless structured buttons
**Learning:** Found that VoiceOver announces raw text in custom structured wrapper buttons (like search result strips and list picker items) without stating the interaction context.
**Action:** Always add `.accessibilityElement(children: .ignore)`, a combined `.accessibilityLabel`, `.accessibilityHint("Double tap to... ")`, and contextual `.accessibilityAddTraits` to these wrapper buttons.
