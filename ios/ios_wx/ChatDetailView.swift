import SwiftUI

struct ChatDetailView: View {
    let peerId: Int
    let peerName: String
    @ObservedObject var net: NetworkManager
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var peerTyping = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { msg in
                            MessageBubble(message: msg, isMe: msg.from_id == net.userId, peerName: peerName)
                                .id(msg.id)
                        }
                        if peerTyping {
                            HStack {
                                Text("对方正在输入...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .onTapGesture { isInputFocused = false }

            Divider()
            inputBar
        }
        .navigationTitle(peerName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadMessages() }
        .onAppear { setupRealtime() }
        .onDisappear { cleanupRealtime() }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Button { } label: {
                Image(systemName: "mic")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            TextField("输入消息...", text: $inputText)
                .textFieldStyle(.roundedBorder)
                .focused($isInputFocused)
                .onSubmit(sendMessage)
                .onChange(of: inputText) {
                    net.sendTyping(toId: peerId)
                }

            if inputText.isEmpty {
                Button { } label: {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(action: sendMessage) {
                    Text("发送")
                        .font(.subheadline).bold()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.07, green: 0.73, blue: 0.37))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }

    func loadMessages() async {
        do {
            messages = try await net.get("/api/messages/\(peerId)")
        } catch { }
    }

    func setupRealtime() {
        net.onNewMessage = { msg in
            let relevant = (msg.from_id == peerId && msg.to_id == net.userId) ||
                           (msg.from_id == net.userId && msg.to_id == peerId)
            if relevant && !messages.contains(where: { $0.id == msg.id }) {
                messages.append(msg)
                peerTyping = false
            }
        }
        net.onTyping = { fromId in
            if fromId == peerId {
                peerTyping = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { peerTyping = false }
            }
        }
        if !net.wsConnected {
            net.startPolling(peerId: peerId)
        }
    }

    func cleanupRealtime() {
        net.onNewMessage = nil
        net.onTyping = nil
        net.stopPolling()
    }

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""

        if net.wsConnected {
            net.sendWSMessage(toId: peerId, text: text)
        } else {
            Task {
                struct Req: Encodable { let to_id: Int; let text: String }
                let _: ChatMessage = try await net.post("/api/messages", Req(to_id: peerId, text: text))
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let isMe: Bool
    var peerName: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isMe { Spacer(minLength: 60) }

            if !isMe {
                AvatarView(systemName: "person.fill", size: 36, bg: .gray)
            }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 2) {
                Text(message.text)
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isMe ? Color(red: 0.58, green: 0.89, blue: 0.38) : Color(white: 0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.05), radius: 1, y: 1)

                Text(formatTime(message.created_at))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if isMe {
                AvatarView(systemName: "person.fill", size: 36, bg: .blue)
            }

            if !isMe { Spacer(minLength: 60) }
        }
    }

    func formatTime(_ s: String) -> String {
        let parts = s.split(separator: " ")
        if parts.count >= 2 {
            let t = parts[1].split(separator: ":")
            if t.count >= 2 { return "\(t[0]):\(t[1])" }
        }
        return s
    }
}
