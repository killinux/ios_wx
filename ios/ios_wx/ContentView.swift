import SwiftUI

struct ContentView: View {
    @StateObject private var net = NetworkManager.shared
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if net.isLoggedIn {
                TabView(selection: $selectedTab) {
                    ChatListView(net: net)
                        .tabItem {
                            Image(systemName: selectedTab == 0 ? "message.fill" : "message")
                            Text("微信")
                        }
                        .tag(0)

                    ContactsView(net: net)
                        .tabItem {
                            Image(systemName: selectedTab == 1 ? "person.2.fill" : "person.2")
                            Text("通讯录")
                        }
                        .tag(1)

                    DiscoverView(net: net)
                        .tabItem {
                            Image(systemName: selectedTab == 2 ? "safari.fill" : "safari")
                            Text("发现")
                        }
                        .tag(2)

                    ProfileView(net: net)
                        .tabItem {
                            Image(systemName: selectedTab == 3 ? "person.fill" : "person")
                            Text("我")
                        }
                        .tag(3)
                }
                .tint(Color(red: 0.07, green: 0.73, blue: 0.37))
                .onAppear { net.connectWS() }
            } else {
                LoginView(net: net)
            }
        }
    }
}

#Preview {
    ContentView()
}
