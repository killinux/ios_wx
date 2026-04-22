import jwt
import time
import hashlib
import secrets
from typing import Optional

SECRET = "ios_wx_secret_key_change_in_production"
ALGORITHM = "HS256"
TOKEN_EXPIRE = 86400 * 30


def hash_password(password: str) -> str:
    salt = secrets.token_hex(16)
    h = hashlib.sha256((salt + password).encode()).hexdigest()
    return f"{salt}${h}"


def verify_password(password: str, hashed: str) -> bool:
    salt, h = hashed.split("$", 1)
    return hashlib.sha256((salt + password).encode()).hexdigest() == h


def create_token(user_id: int) -> str:
    payload = {"uid": user_id, "exp": int(time.time()) + TOKEN_EXPIRE}
    return jwt.encode(payload, SECRET, algorithm=ALGORITHM)


def decode_token(token: str) -> Optional[int]:
    try:
        payload = jwt.decode(token, SECRET, algorithms=[ALGORITHM])
        return payload["uid"]
    except (jwt.ExpiredSignatureError, jwt.InvalidTokenError):
        return None
