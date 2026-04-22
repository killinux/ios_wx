import SwiftUI

struct ProfileView: View {
    @ObservedObject var net: NetworkManager

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(.blue.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(net.nickname)
                                .font(.title3).bold()
                            HStack(spacing: 4) {
                                Text("ID: \(net.userId)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "qrcode")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    ProfileRow(icon: "creditcard.fill", color: .blue, title: "服务")
                }

                Section {
                    ProfileRow(icon: "star.fill", color: .yellow, title: "收藏")
                    ProfileRow(icon: "face.smiling.fill", color: .orange, title: "表情")
                    ProfileRow(icon: "photo.fill", color: .green, title: "朋友圈")
                }

                Section {
                    ProfileRow(icon: "gearshape.fill", color: .gray, title: "设置")
                }

                Section {
                    Button(role: .destructive) {
                        net.logout()
                    } label: {
                        Text("退出登录")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("我")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct ProfileRow: View {
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
