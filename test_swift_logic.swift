import Foundation

let lower = "buy milk in wal"
let t = "in "

let comp = lower.components(separatedBy: t).last ?? ""

let possibleSuffix: String
if let range = lower.range(of: t, options: .backwards) {
    possibleSuffix = String(lower[range.upperBound...])
} else {
    possibleSuffix = lower
}

print("comp:", comp)
print("possible:", possibleSuffix)
print("match:", comp == possibleSuffix)
