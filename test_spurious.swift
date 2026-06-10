import SwiftUI

class A: ObservableObject {
    @Published var val = ""
}

struct TestView: View {
    @StateObject var a = A()
    @State var text = ""
    
    var body: some View {
        Text(text)
            .onReceive(a.$val) { newVal in
                if newVal.isEmpty { return }
                print("onReceive: \(newVal)")
                text = newVal
            }
            .onChange(of: text) { old, new in
                print("onChange: new='\(new)', a.val='\(a.val)'")
                if new != a.val {
                    print("SPURIOUS!")
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    a.val = "hello"
                }
            }
    }
}
