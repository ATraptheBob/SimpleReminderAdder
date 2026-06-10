import Foundation
import Combine

class A: ObservableObject {
    @Published var val = "old"
}

let a = A()
var c: AnyCancellable?
c = a.$val.sink { newVal in
    print("sink received: \(newVal), current a.val: \(a.val)")
}

a.val = "new"
print("after assignment, a.val: \(a.val)")
