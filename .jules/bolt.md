## 2024-06-13 - Optimize List Matching O(N*M) loop inside QuickAddView
**Learning:** In Swift, calling `components(separatedBy:)` on a string inside a nested loop causes a huge amount of redundant memory allocations and computationally expensive string processing, especially when the outer loop iterates over a large collection (like multiple EKCalendars).
**Action:** Hoist repetitive string manipulations outside of nested loops by pre-computing them into a collection (e.g., using `map`). This drastically lowers the algorithmic complexity.
