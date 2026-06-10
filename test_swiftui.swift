import SwiftUI

class A: ObservableObject {
    @Published var val = "old"
}

struct TestView: View {
    @StateObject var a = A()
    @State var text = "old"
    
    var body: some View {
        Text(text)
            .onReceive(a.$val) { newVal in
                print("onReceive: \(newVal)")
                text = newVal
            }
            .onChange(of: text) { old, new in
                print("onChange: new=\(new), a.val=\(a.val)")
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    a.val = "new"
                }
            }
    }
}
