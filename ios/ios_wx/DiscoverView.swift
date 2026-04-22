import SwiftUI

struct DiscoverView: View {
    @ObservedObject var net: NetworkManager

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(destination: MomentsView(net: net)) {
                        DiscoverRow(icon: "circle.grid.2x2.fill", color: .orange, title: "朋友圈")
                    }
                    DiscoverRow(icon: "video.fill", color: .orange, title: "视频号")
                }

                Section {
                    DiscoverRow(icon: "qrcode.viewfinder", color: .blue, title: "扫一扫")
                    DiscoverRow(icon: "hand.wave.fill", color: .blue, title: "摇一摇")
                }

                Section {
                    DiscoverRow(icon: "bag.fill", color: .pink, title: "购物")
                    DiscoverRow(icon: "gamecontroller.fill", color: .green, title: "游戏")
                }

                Section {
                    DiscoverRow(icon: "text.book.closed.fill", color: .purple, title: "小程序")
                }
            }
            .navigationTitle("发现")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct DiscoverRow: View {
    let icon: String
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(title)
        }
        .padding(.vertical, 2)
    }
}

struct MomentsView: View {
    @ObservedObject var net: NetworkManager
    @State private var moments: [MomentItem] = []
    @State private var showPost = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    Rectangle()
                        .fill(
                            LinearGradient(colors: [.blue.opacity(0.6), .purple.opacity(0.4)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(height: 260)

                    HStack(spacing: 10) {
                        Text(net.nickname)
                            .font(.headline)
                            .foregroundStyle(.white)
                        AvatarView(systemName: "person.fill", size: 60, bg: .blue)
                    }
                    .padding()
                }

                LazyVStack(spacing: 0) {
                    ForEach(moments) { moment in
                        MomentCell(moment: moment, net: net) {
                            Task { await loadMoments() }
                        }
                        Divider().padding(.leading, 60)
                    }
                }
            }
        }
        .navigationTitle("朋友圈")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showPost = true } label: {
                    Image(systemName: "camera")
                }
            }
        }
        .task { await loadMoments() }
        .sheet(isPresented: $showPost) {
            PostMomentView(net: net) { Task { await loadMoments() } }
        }
    }

    func loadMoments() async {
        do {
            moments = try await net.get("/api/moments")
        } catch { }
    }
}

struct MomentCell: View {
    let moment: MomentItem
    @ObservedObject var net: NetworkManager
    var onLikeToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(systemName: "person.fill", size: 42, bg: .gray)

            VStack(alignment: .leading, spacing: 6) {
                Text(moment.nickname)
                    .font(.subheadline).bold()
                    .foregroundStyle(Color(red: 0.33, green: 0.42, blue: 0.56))

                Text(moment.text)
                    .font(.subheadline)

                HStack {
                    Text(moment.created_at)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task {
                            struct Empty: Encodable {}
                            let _: OkResponse = try await net.post("/api/moments/\(moment.id)/like", Empty())
                            onLikeToggle()
                        }
                    } label: {
                        Image(systemName: "heart")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !moment.likes.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                        Text(moment.likes.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(6)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

struct PostMomentView: View {
    @ObservedObject var net: NetworkManager
    var onPosted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack {
                TextEditor(text: $text)
                    .frame(minHeight: 150)
                    .padding()
                Spacer()
            }
            .navigationTitle("发朋友圈")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("发表") {
                        guard !text.isEmpty else { return }
                        Task {
                            struct Req: Encodable { let text: String; let images: [String] }
                            let _: OkResponse = try await net.post("/api/moments", Req(text: text, images: []))
                            onPosted()
                            dismiss()
                        }
                    }
                    .bold()
                }
            }
        }
    }
}
