"""Autenticação de usuários — hash de senha e helpers."""

from __future__ import annotations

import hashlib
import hmac
import secrets

from sqlalchemy.orm import Session

from app.models import User

_PBKDF2_ITERATIONS = 260_000


def hash_password(password: str) -> str:
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt.encode("utf-8"),
        _PBKDF2_ITERATIONS,
    ).hex()
    return f"pbkdf2_sha256${_PBKDF2_ITERATIONS}${salt}${digest}"


def verify_password(password: str, password_hash: str) -> bool:
    try:
        algo, iterations_str, salt, expected = password_hash.split("$", 3)
        if algo != "pbkdf2_sha256":
            return False
        iterations = int(iterations_str)
        digest = hashlib.pbkdf2_hmac(
            "sha256",
            password.encode("utf-8"),
            salt.encode("utf-8"),
            iterations,
        ).hex()
        return hmac.compare_digest(digest, expected)
    except (ValueError, TypeError):
        return False


def get_user_by_id(db: Session, user_id: int) -> User | None:
    return db.query(User).filter(User.id == user_id, User.is_active.is_(True)).first()


def get_user_by_username(db: Session, username: str) -> User | None:
    return (
        db.query(User)
        .filter(User.username == username, User.is_active.is_(True))
        .first()
    )


def authenticate_user(db: Session, username: str, password: str) -> User | None:
    user = get_user_by_username(db, username.strip().lower())
    if not user or not verify_password(password, user.password_hash):
        return None
    return user


def ensure_seed_users(db: Session) -> dict[str, User]:
    """Cria admin e demo se ausentes; retorna mapa username → User."""
    users: dict[str, User] = {}
    for username, password in (("admin", "admin"), ("demo", "demo")):
        existing = db.query(User).filter(User.username == username).first()
        if existing:
            users[username] = existing
            continue
        user = User(
            username=username,
            password_hash=hash_password(password),
            is_active=True,
        )
        db.add(user)
        users[username] = user
    db.commit()
    for username in users:
        db.refresh(users[username])
    return users
