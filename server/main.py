"""
微信 iOS 后端 — FastAPI + WebSocket + HTTP 轮询兜底
启动: uvicorn main:app --host 0.0.0.0 --port 8080
"""
import json
import time
import asyncio
from contextlib import asynccontextmanager
from typing import Optional

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, Depends, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from database import get_db, init_db
from auth import hash_password, verify_password, create_token, decode_token


# ── WebSocket connection manager ──

class ConnectionManager:
    def __init__(self):
        self.active: dict[int, list[WebSocket]] = {}

    async def connect(self, user_id: int, ws: WebSocket):
        await ws.accept()
        self.active.setdefault(user_id, []).append(ws)

    def disconnect(self, user_id: int, ws: WebSocket):
        conns = self.active.get(user_id, [])
        if ws in conns:
            conns.remove(ws)
        if not conns:
            self.active.pop(user_id, None)

    async def send_to_user(self, user_id: int, data: dict):
        for ws in self.active.get(user_id, []):
            try:
                await ws.send_json(data)
            except Exception:
                pass

    def is_online(self, user_id: int) -> bool:
        return bool(self.active.get(user_id))


manager = ConnectionManager()


# ── App ──

@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield

app = FastAPI(title="ios_wx server", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], allow_methods=["*"], allow_headers=["*"],
)


# ── Auth dependency ──

def current_user(token: str = Query(None, alias="token")) -> int:
    if not token:
        raise HTTPException(401, "token required")
    uid = decode_token(token)
    if uid is None:
        raise HTTPException(401, "invalid token")
    return uid


# ── Models ──

class RegisterReq(BaseModel):
    username: str
    nickname: str
    password: str

class LoginReq(BaseModel):
    username: str
    password: str

class SendMessageReq(BaseModel):
    to_id: int
    text: str

class PostMomentReq(BaseModel):
    text: str
    images: list[str] = []

class AddContactReq(BaseModel):
    contact_id: int


# ── Auth routes ──

@app.post("/api/register")
def register(req: RegisterReq):
    db = get_db()
    existing = db.execute("SELECT id FROM users WHERE username=?", (req.username,)).fetchone()
    if existing:
        raise HTTPException(400, "username taken")
    cur = db.execute(
        "INSERT INTO users (username, nickname, password_hash) VALUES (?,?,?)",
        (req.username, req.nickname, hash_password(req.password)),
    )
    db.commit()
    uid = cur.lastrowid
    token = create_token(uid)
    db.execute("UPDATE users SET token=? WHERE id=?", (token, uid))
    db.commit()
    return {"id": uid, "token": token, "nickname": req.nickname}


@app.post("/api/login")
def login(req: LoginReq):
    db = get_db()
    row = db.execute("SELECT id, nickname, password_hash FROM users WHERE username=?", (req.username,)).fetchone()
    if not row or not verify_password(req.password, row["password_hash"]):
        raise HTTPException(401, "wrong username or password")
    token = create_token(row["id"])
    db.execute("UPDATE users SET token=? WHERE id=?", (token, row["id"]))
    db.commit()
    return {"id": row["id"], "token": token, "nickname": row["nickname"]}


@app.get("/api/me")
def get_me(uid: int = Depends(current_user)):
    db = get_db()
    row = db.execute("SELECT id, username, nickname, avatar FROM users WHERE id=?", (uid,)).fetchone()
    if not row:
        raise HTTPException(404, "user not found")
    return dict(row)


# ── Contacts ──

@app.get("/api/contacts")
def list_contacts(uid: int = Depends(current_user)):
    db = get_db()
    rows = db.execute("""
        SELECT u.id, u.username, u.nickname, u.avatar
        FROM contacts c JOIN users u ON u.id = c.contact_id
        WHERE c.user_id = ?
        ORDER BY u.nickname
    """, (uid,)).fetchall()
    return [dict(r) for r in rows]


@app.post("/api/contacts")
def add_contact(req: AddContactReq, uid: int = Depends(current_user)):
    db = get_db()
    target = db.execute("SELECT id FROM users WHERE id=?", (req.contact_id,)).fetchone()
    if not target:
        raise HTTPException(404, "user not found")
    db.execute("INSERT OR IGNORE INTO contacts (user_id, contact_id) VALUES (?,?)", (uid, req.contact_id))
    db.execute("INSERT OR IGNORE INTO contacts (user_id, contact_id) VALUES (?,?)", (req.contact_id, uid))
    db.commit()
    return {"ok": True}


@app.get("/api/users/search")
def search_users(q: str, uid: int = Depends(current_user)):
    db = get_db()
    rows = db.execute(
        "SELECT id, username, nickname, avatar FROM users WHERE (username LIKE ? OR nickname LIKE ?) AND id != ?",
        (f"%{q}%", f"%{q}%", uid),
    ).fetchall()
    return [dict(r) for r in rows]


# ── Chats (conversation list) ──

@app.get("/api/chats")
def list_chats(uid: int = Depends(current_user)):
    db = get_db()
    rows = db.execute("""
        SELECT
            m.id, m.from_id, m.to_id, m.text, m.created_at,
            CASE WHEN m.from_id = ? THEN m.to_id ELSE m.from_id END AS peer_id
        FROM messages m
        INNER JOIN (
            SELECT MAX(id) AS max_id
            FROM messages
            WHERE from_id = ? OR to_id = ?
            GROUP BY CASE WHEN from_id = ? THEN to_id ELSE from_id END
        ) latest ON m.id = latest.max_id
        ORDER BY m.created_at DESC
    """, (uid, uid, uid, uid)).fetchall()

    chats = []
    for r in rows:
        peer = db.execute("SELECT id, nickname, avatar FROM users WHERE id=?", (r["peer_id"],)).fetchone()
        unread = db.execute(
            "SELECT COUNT(*) as c FROM messages WHERE from_id=? AND to_id=? AND id > COALESCE((SELECT MAX(id) FROM messages WHERE from_id=? AND to_id=?), 0)",
            (r["peer_id"], uid, uid, r["peer_id"]),
        ).fetchone()
        chats.append({
            "peer_id": r["peer_id"],
            "peer_name": peer["nickname"] if peer else "未知",
            "peer_avatar": peer["avatar"] if peer else "",
            "last_message": r["text"],
            "last_time": r["created_at"],
            "unread": unread["c"] if unread else 0,
        })
    return chats


# ── Messages ──

@app.post("/api/messages")
async def send_message(req: SendMessageReq, uid: int = Depends(current_user)):
    db = get_db()
    cur = db.execute(
        "INSERT INTO messages (from_id, to_id, text) VALUES (?,?,?)",
        (uid, req.to_id, req.text),
    )
    db.commit()
    msg_id = cur.lastrowid
    row = db.execute("SELECT id, from_id, to_id, text, created_at FROM messages WHERE id=?", (msg_id,)).fetchone()
    msg = dict(row)

    await manager.send_to_user(req.to_id, {"type": "new_message", "message": msg})
    await manager.send_to_user(uid, {"type": "new_message", "message": msg})
    return msg


@app.get("/api/messages/{peer_id}")
def get_messages(peer_id: int, before: Optional[int] = None, limit: int = 50, uid: int = Depends(current_user)):
    db = get_db()
    if before:
        rows = db.execute("""
            SELECT id, from_id, to_id, text, created_at FROM messages
            WHERE ((from_id=? AND to_id=?) OR (from_id=? AND to_id=?)) AND id < ?
            ORDER BY id DESC LIMIT ?
        """, (uid, peer_id, peer_id, uid, before, limit)).fetchall()
    else:
        rows = db.execute("""
            SELECT id, from_id, to_id, text, created_at FROM messages
            WHERE (from_id=? AND to_id=?) OR (from_id=? AND to_id=?)
            ORDER BY id DESC LIMIT ?
        """, (uid, peer_id, peer_id, uid, limit)).fetchall()
    return [dict(r) for r in reversed(rows)]


@app.get("/api/messages/poll/{peer_id}")
def poll_messages(peer_id: int, after: int = 0, uid: int = Depends(current_user)):
    """HTTP 轮询兜底：获取 after 之后的新消息"""
    db = get_db()
    rows = db.execute("""
        SELECT id, from_id, to_id, text, created_at FROM messages
        WHERE ((from_id=? AND to_id=?) OR (from_id=? AND to_id=?)) AND id > ?
        ORDER BY id ASC
    """, (uid, peer_id, peer_id, uid, after)).fetchall()
    return [dict(r) for r in rows]


# ── Moments ──

@app.get("/api/moments")
def list_moments(uid: int = Depends(current_user)):
    db = get_db()
    contact_ids = [r["contact_id"] for r in db.execute("SELECT contact_id FROM contacts WHERE user_id=?", (uid,)).fetchall()]
    contact_ids.append(uid)
    placeholders = ",".join("?" * len(contact_ids))
    rows = db.execute(f"""
        SELECT m.id, m.user_id, m.text, m.images, m.created_at, u.nickname, u.avatar
        FROM moments m JOIN users u ON u.id = m.user_id
        WHERE m.user_id IN ({placeholders})
        ORDER BY m.created_at DESC LIMIT 50
    """, contact_ids).fetchall()

    result = []
    for r in rows:
        likes = db.execute("""
            SELECT u.nickname FROM moment_likes ml JOIN users u ON u.id = ml.user_id
            WHERE ml.moment_id = ?
        """, (r["id"],)).fetchall()
        result.append({
            **dict(r),
            "images": json.loads(r["images"]),
            "likes": [l["nickname"] for l in likes],
        })
    return result


@app.post("/api/moments")
def post_moment(req: PostMomentReq, uid: int = Depends(current_user)):
    db = get_db()
    cur = db.execute(
        "INSERT INTO moments (user_id, text, images) VALUES (?,?,?)",
        (uid, req.text, json.dumps(req.images)),
    )
    db.commit()
    return {"id": cur.lastrowid}


@app.post("/api/moments/{moment_id}/like")
def toggle_like(moment_id: int, uid: int = Depends(current_user)):
    db = get_db()
    existing = db.execute("SELECT 1 FROM moment_likes WHERE moment_id=? AND user_id=?", (moment_id, uid)).fetchone()
    if existing:
        db.execute("DELETE FROM moment_likes WHERE moment_id=? AND user_id=?", (moment_id, uid))
    else:
        db.execute("INSERT INTO moment_likes (moment_id, user_id) VALUES (?,?)", (moment_id, uid))
    db.commit()
    return {"liked": not existing}


# ── WebSocket ──

@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket, token: str = Query(...)):
    uid = decode_token(token)
    if uid is None:
        await ws.close(code=4001, reason="invalid token")
        return

    await manager.connect(uid, ws)
    try:
        while True:
            data = await ws.receive_json()
            msg_type = data.get("type")

            if msg_type == "ping":
                await ws.send_json({"type": "pong"})

            elif msg_type == "send_message":
                to_id = data.get("to_id")
                text = data.get("text", "")
                if not to_id or not text:
                    continue
                db = get_db()
                cur = db.execute(
                    "INSERT INTO messages (from_id, to_id, text) VALUES (?,?,?)",
                    (uid, to_id, text),
                )
                db.commit()
                row = db.execute("SELECT id, from_id, to_id, text, created_at FROM messages WHERE id=?", (cur.lastrowid,)).fetchone()
                msg = dict(row)
                await manager.send_to_user(to_id, {"type": "new_message", "message": msg})
                await manager.send_to_user(uid, {"type": "new_message", "message": msg})

            elif msg_type == "typing":
                to_id = data.get("to_id")
                if to_id:
                    await manager.send_to_user(to_id, {"type": "typing", "from_id": uid})

    except WebSocketDisconnect:
        manager.disconnect(uid, ws)
    except Exception:
        manager.disconnect(uid, ws)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
