import SwiftUI

struct ContentView: View {
    var body: some View {
        RootView()
            .environmentObject(PasswordViewModel())
    }
}

#Preview {
    ContentView()
}
