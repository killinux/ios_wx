import SwiftUI

struct ChatListView: View {
    @ObservedObject var net: NetworkManager
    @State private var chats: [ChatItem] = []
    @State private var searchText = ""

    var filteredChats: [ChatItem] {
        if searchText.isEmpty { return chats }
        return chats.filter { $0.peer_name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredChats) { chat in
                    NavigationLink(destination: ChatDetailView(peerId: chat.peer_id, peerName: chat.peer_name, net: net)) {
                        ChatRow(chat: chat)
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "搜索")
            .navigationTitle("微信")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { } label: {
                            Label("发起群聊", systemImage: "person.2")
                        }
                        Button { } label: {
                            Label("添加朋友", systemImage: "person.badge.plus")
                        }
                        Button { } label: {
                            Label("扫一扫", systemImage: "qrcode.viewfinder")
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.title3)
                    }
                }
            }
            .refreshable { await loadChats() }
            .task { await loadChats() }
        }
    }

    func loadChats() async {
        do {
            chats = try await net.get("/api/chats")
        } catch { }
    }
}

struct ChatRow: View {
    let chat: ChatItem

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                AvatarView(systemName: "person.fill", size: 48, bg: .gray)

                if chat.unread > 0 {
                    Text(chat.unread > 99 ? "99+" : "\(chat.unread)")
                        .font(.caption2).bold()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.red)
                        .clipShape(Capsule())
                        .offset(x: 6, y: -4)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(chat.peer_name)
                        .font(.body)
                        .lineLimit(1)
                    Spacer()
                    Text(formatTime(chat.last_time))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(chat.last_message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    func formatTime(_ s: String) -> String {
        let parts = s.split(separator: " ")
        if parts.count >= 2 {
            let timeParts = parts[1].split(separator: ":")
            if timeParts.count >= 2 { return "\(timeParts[0]):\(timeParts[1])" }
        }
        return s
    }
}

struct AvatarView: View {
    let systemName: String
    var size: CGFloat = 48
    var bg: Color = .gray

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.4))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(bg.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
