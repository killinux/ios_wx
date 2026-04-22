import jwt
import time
from passlib.hash import bcrypt

SECRET = "ios_wx_secret_key_change_in_production"
ALGORITHM = "HS256"
TOKEN_EXPIRE = 86400 * 30


def hash_password(password: str) -> str:
    return bcrypt.hash(password)


def verify_password(password: str, hashed: str) -> bool:
    return bcrypt.verify(password, hashed)


def create_token(user_id: int) -> str:
    payload = {"uid": user_id, "exp": int(time.time()) + TOKEN_EXPIRE}
    return jwt.encode(payload, SECRET, algorithm=ALGORITHM)


def decode_token(token: str) -> int | None:
    try:
        payload = jwt.decode(token, SECRET, algorithms=[ALGORITHM])
        return payload["uid"]
    except (jwt.ExpiredSignatureError, jwt.InvalidTokenError):
        return None
