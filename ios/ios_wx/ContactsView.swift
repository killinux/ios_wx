import SwiftUI

struct ContactsView: View {
    @ObservedObject var net: NetworkManager
    @State private var contacts: [UserInfo] = []
    @State private var searchText = ""
    @State private var showAddFriend = false

    var grouped: [(String, [UserInfo])] {
        let filtered = searchText.isEmpty ? contacts :
            contacts.filter { $0.nickname.localizedCaseInsensitiveContains(searchText) }
        let dict = Dictionary(grouping: filtered) { String($0.nickname.first ?? Character("?")) }
        return dict.sorted { $0.key < $1.key }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ContactFunctionRow(icon: "person.badge.plus", color: .orange, title: "新的朋友")
                        .onTapGesture { showAddFriend = true }
                    ContactFunctionRow(icon: "person.2", color: .green, title: "群聊")
                    ContactFunctionRow(icon: "building.2", color: .blue, title: "公众号")
                }

                ForEach(grouped, id: \.0) { initial, users in
                    Section(header: Text(initial)) {
                        ForEach(users) { user in
                            NavigationLink(destination: ChatDetailView(peerId: user.id, peerName: user.nickname, net: net)) {
                                HStack(spacing: 12) {
                                    AvatarView(systemName: "person.fill", size: 40, bg: .gray)
                                    Text(user.nickname)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }

                Section {
                    Text("\(contacts.count)位联系人")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "搜索")
            .navigationTitle("通讯录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddFriend = true } label: {
                        Image(systemName: "person.badge.plus")
                    }
                }
            }
            .refreshable { await loadContacts() }
            .task { await loadContacts() }
            .sheet(isPresented: $showAddFriend) {
                AddFriendView(net: net) { await loadContacts() }
            }
        }
    }

    func loadContacts() async {
        do {
            contacts = try await net.get("/api/contacts")
        } catch { }
    }
}

struct ContactFunctionRow: View {
    let icon: String
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(title)
        }
        .padding(.vertical, 2)
    }
}

struct AddFriendView: View {
    @ObservedObject var net: NetworkManager
    var onAdded: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [UserInfo] = []
    @State private var addedIds: Set<Int> = []

    var body: some View {
        NavigationStack {
            VStack {
                HStack {
                    TextField("搜索用户名或昵称", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await search() } }
                    Button("搜索") { Task { await search() } }
                }
                .padding()

                List(results) { user in
                    HStack {
                        AvatarView(systemName: "person.fill", size: 40, bg: .gray)
                        VStack(alignment: .leading) {
                            Text(user.nickname).font(.body)
                            Text(user.username).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if addedIds.contains(user.id) {
                            Text("已添加").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("添加") { Task { await addFriend(user.id) } }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        }
                    }
                }
            }
            .navigationTitle("添加朋友")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    func search() async {
        guard !query.isEmpty else { return }
        do {
            results = try await net.get("/api/users/search?q=\(query)")
        } catch { }
    }

    func addFriend(_ id: Int) async {
        do {
            struct Req: Encodable { let contact_id: Int }
            let _: OkResponse = try await net.post("/api/contacts", Req(contact_id: id))
            addedIds.insert(id)
            await onAdded()
        } catch { }
    }
}
