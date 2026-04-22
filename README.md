# ios_wx — 微信 iOS 客户端 + Python 服务端

仿微信 iOS App，包含完整的前后端。

## 架构

```
┌──────────────┐     WebSocket / HTTP      ┌──────────────────┐
│  iOS Client  │  ◄─────────────────────►  │  FastAPI Server  │
│  (SwiftUI)   │                           │  (Python 3.9+)   │
└──────────────┘                           └────────┬─────────┘
                                                    │
                                                    ▼
                                              ┌──────────┐
                                              │  SQLite   │
                                              └──────────┘
```

### 通信方式
- **主通道：WebSocket** — 实时消息推送、正在输入提示、心跳保活
- **兜底：HTTP 轮询** — WebSocket 连接失败重试 5 次后，自动降级为 3 秒 HTTP 轮询

## 功能

| 功能 | 说明 |
|------|------|
| 注册/登录 | 用户名 + 密码，JWT token 认证 |
| 聊天 | 一对一实时聊天，消息气泡，输入提示 |
| 通讯录 | 联系人列表，搜索用户，添加好友 |
| 朋友圈 | 发布动态，点赞 |
| 个人中心 | 查看个人信息，退出登录 |

## 目录结构

```
ios_wx/
├── server/                 # Python 服务端
│   ├── main.py             # FastAPI 主程序（API + WebSocket）
│   ├── database.py         # SQLite 数据库初始化
│   ├── auth.py             # 密码哈希 + JWT token
│   ├── requirements.txt    # Python 依赖
│   └── run.sh              # 启动脚本
├── ios/                    # iOS 客户端
│   ├── ios_wx.xcodeproj/   # Xcode 项目文件
│   └── ios_wx/             # Swift 源码
│       ├── ios_wxApp.swift       # App 入口
│       ├── ContentView.swift     # 主 TabView
│       ├── LoginView.swift       # 登录/注册页
│       ├── NetworkManager.swift  # 网络层（WebSocket + HTTP）
│       ├── ChatListView.swift    # 聊天列表
│       ├── ChatDetailView.swift  # 聊天详情（消息气泡）
│       ├── ContactsView.swift    # 通讯录
│       ├── DiscoverView.swift    # 发现页 + 朋友圈
│       └── ProfileView.swift     # 个人中心
└── README.md
```

## 服务端部署

### 环境要求
- Python 3.9+
- Linux 服务器（已部署在腾讯云 49.233.189.223）

### 启动

```bash
cd server

# 首次运行，自动创建 venv 并安装依赖
chmod +x run.sh
./run.sh

# 或手动启动
python3 -m venv venv
./venv/bin/pip install -r requirements.txt
./venv/bin/uvicorn main:app --host 0.0.0.0 --port 8086
```

服务启动后，API 文档可访问：`http://<服务器IP>:8086/docs`

### API 列表

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/register` | 注册（username, nickname, password） |
| POST | `/api/login` | 登录（username, password） |
| GET | `/api/me` | 获取当前用户信息 |
| GET | `/api/contacts` | 联系人列表 |
| POST | `/api/contacts` | 添加好友（contact_id） |
| GET | `/api/users/search?q=xxx` | 搜索用户 |
| GET | `/api/chats` | 会话列表 |
| POST | `/api/messages` | 发送消息（to_id, text） |
| GET | `/api/messages/{peer_id}` | 获取聊天记录 |
| GET | `/api/messages/poll/{peer_id}?after=N` | HTTP 轮询新消息 |
| GET | `/api/moments` | 朋友圈列表 |
| POST | `/api/moments` | 发朋友圈（text, images） |
| POST | `/api/moments/{id}/like` | 点赞/取消 |
| WS | `/ws?token=xxx` | WebSocket 实时通道 |

所有 HTTP 接口通过 `?token=xxx` 传递认证 token。

### WebSocket 消息格式

**发送消息：**
```json
{"type": "send_message", "to_id": 2, "text": "你好"}
```

**接收新消息：**
```json
{"type": "new_message", "message": {"id": 1, "from_id": 2, "to_id": 1, "text": "你好", "created_at": "..."}}
```

**正在输入：**
```json
{"type": "typing", "to_id": 2}
```

**心跳：**
```json
{"type": "ping"}  →  {"type": "pong"}
```

## iOS 客户端

### 环境要求
- macOS + Xcode 26+
- iOS 26.4+ 模拟器或真机

### 配置服务器地址

编辑 `ios/ios_wx/NetworkManager.swift`，修改 `baseURL`：

```swift
let baseURL = "http://你的服务器IP:8086"
```

### 编译运行

1. 用 Xcode 打开 `ios/ios_wx.xcodeproj`
2. 选择模拟器（iPhone 17 Pro 等）
3. Cmd+R 运行

### ATS 配置

项目根目录 `Info.plist` 已配置 `NSAllowsArbitraryLoads = true`，允许 HTTP 明文请求。生产环境应改为 HTTPS。

### 使用流程

1. 打开 App，点击"没有账号？注册"
2. 填写用户名、昵称、密码，点击注册
3. 注册成功自动登录，进入聊天列表
4. 在「通讯录」Tab 点击右上角添加好友
5. 搜索其他用户的用户名或昵称，点击添加
6. 在通讯录中点击好友进入聊天
7. 在「发现」Tab 可以查看和发布朋友圈

## 数据库

SQLite 数据库文件 `wechat.db` 在 server 目录下自动创建。

表结构：
- `users` — 用户（id, username, nickname, password_hash, avatar, token）
- `contacts` — 好友关系（user_id, contact_id）
- `messages` — 聊天消息（id, from_id, to_id, text, created_at）
- `moments` — 朋友圈（id, user_id, text, images, created_at）
- `moment_likes` — 点赞（moment_id, user_id）
