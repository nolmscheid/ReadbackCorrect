import SwiftUI

struct RootTabView: View {

    @ObservedObject var ATCRecognizer: ATCLiveRecognizer
    @ObservedObject var ATISRecognizer: ATISLiveRecognizer
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {

            ATCView(atcRecognizer: ATCRecognizer)
                .tabItem {
                    Image(systemName: "airplane")
                    Text("ATC")
                }
                .tag(0)

            IFRView(atcRecognizer: ATCRecognizer)
                .tabItem {
                    Image(systemName: "doc.text")
                    Text("IFR")
                }
                .tag(1)

            ATISView(recognizer: ATISRecognizer)
                .tabItem {
                    Image(systemName: "waveform")
                    Text("ATIS")
                }
                .tag(2)

            SettingsView(atcRecognizer: ATCRecognizer)
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("SETTINGS")
                }
                .tag(3)
        }
        .onChange(of: selectedTab) { _, new in
            ATCRecognizer.commitOnlyOnTap = (new == 1)
        }
        .onAppear {
            ATCRecognizer.commitOnlyOnTap = (selectedTab == 1)
        }
    }
}

