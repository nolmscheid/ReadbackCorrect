import SwiftUI

struct ContentView: View {

    @StateObject private var ATCRecognizer = ATCLiveRecognizer()
    @StateObject private var ATISRecognizer = ATISLiveRecognizer()

    var body: some View {
        RootTabView(
            ATCRecognizer: ATCRecognizer,
            ATISRecognizer: ATISRecognizer
        )
    }
}

#Preview {
    ContentView()
}
