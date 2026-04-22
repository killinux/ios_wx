import SwiftUI

struct LoginView: View {
    @ObservedObject var net: NetworkManager
    @State private var username = ""
    @State private var password = ""
    @State private var nickname = ""
    @State private var isRegister = false
    @State private var error = ""
    @State private var loading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "message.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Color(red: 0.07, green: 0.73, blue: 0.37))
                    .padding(.top, 60)

                Text(isRegister ? "注册" : "登录")
                    .font(.largeTitle).bold()

                VStack(spacing: 14) {
                    TextField("用户名", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if isRegister {
                        TextField("昵称", text: $nickname)
                            .textFieldStyle(.roundedBorder)
                    }

                    SecureField("密码", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal, 30)

                if !error.isEmpty {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Button(action: submit) {
                    if loading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(isRegister ? "注册" : "登录")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.07, green: 0.73, blue: 0.37))
                .padding(.horizontal, 30)
                .disabled(loading)

                Button(isRegister ? "已有账号？登录" : "没有账号？注册") {
                    isRegister.toggle()
                    error = ""
                }
                .font(.subheadline)

                Spacer()
            }
        }
    }

    func submit() {
        guard !username.isEmpty, !password.isEmpty else {
            error = "请填写完整"
            return
        }
        if isRegister && nickname.isEmpty {
            error = "请输入昵称"
            return
        }
        loading = true
        error = ""

        Task {
            do {
                let resp: AuthResponse
                if isRegister {
                    struct Reg: Encodable { let username, nickname, password: String }
                    resp = try await net.post("/api/register", Reg(username: username, nickname: nickname, password: password))
                } else {
                    struct Login: Encodable { let username, password: String }
                    resp = try await net.post("/api/login", Login(username: username, password: password))
                }
                await MainActor.run {
                    net.saveAuth(id: resp.id, token: resp.token, nickname: resp.nickname)
                    net.connectWS()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.loading = false
                }
            }
        }
    }
}
