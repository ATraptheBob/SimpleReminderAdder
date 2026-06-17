import Foundation

struct List {
    var title: String
}

func benchmark() {
    let lists = (1...100).map { List(title: "List \($0)") } + [List(title: "Walmart")]
    let taskText = "buy milk in wal"
    let lower = taskText.lowercased()
    let listTriggers = ["in ", "to ", "at ", "on ", "for "]

    var dummy = ""

    let startOriginal = CFAbsoluteTimeGetCurrent()
    for _ in 0..<10000 {
        for trigger in listTriggers {
            if lower.hasSuffix(trigger) {
                dummy = lists.first?.title ?? ""
                break
            }
            for list in lists {
                let listLower = list.title.lowercased()
                for t in listTriggers {
                    if lower.hasSuffix(t) { break }
                    let possibleSuffix = lower.components(separatedBy: t).last ?? ""
                    if !possibleSuffix.isEmpty && listLower.hasPrefix(possibleSuffix) && possibleSuffix != listLower {
                        dummy = String(list.title.dropFirst(possibleSuffix.count))
                        break
                    }
                }
                if !dummy.isEmpty { break }
            }
            if !dummy.isEmpty { break }
        }
        dummy = ""
    }
    let endOriginal = CFAbsoluteTimeGetCurrent()

    let startOptimized = CFAbsoluteTimeGetCurrent()
    for _ in 0..<10000 {
        var found = false
        for trigger in listTriggers {
            if lower.hasSuffix(trigger) {
                dummy = lists.first?.title ?? ""
                found = true
                break
            }
        }

        if !found {
            // Find possible suffixes first
            var possibleSuffixes: [String] = []
            for t in listTriggers {
                if lower.hasSuffix(t) { continue }
                if let range = lower.range(of: t, options: .backwards) {
                    let possibleSuffix = String(lower[range.upperBound...])
                    if !possibleSuffix.isEmpty {
                        possibleSuffixes.append(possibleSuffix)
                    }
                }
            }

            for list in lists {
                let listLower = list.title.lowercased()
                for possibleSuffix in possibleSuffixes {
                    if listLower.hasPrefix(possibleSuffix) && possibleSuffix != listLower {
                        dummy = String(list.title.dropFirst(possibleSuffix.count))
                        found = true
                        break
                    }
                }
                if found { break }
            }
        }
        dummy = ""
    }
    let endOptimized = CFAbsoluteTimeGetCurrent()

    print("Original: \(endOriginal - startOriginal) seconds")
    print("Optimized: \(endOptimized - startOptimized) seconds")
}

benchmark()
