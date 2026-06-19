"""Middleware e dependências de autenticação."""

from __future__ import annotations

import logging
from urllib.parse import quote

from fastapi import Depends, HTTPException, Request
from fastapi.responses import JSONResponse, RedirectResponse
from sqlalchemy.orm import Session
from starlette.middleware.base import BaseHTTPMiddleware

from app.auth import get_user_by_id
from app.database import SessionLocal
from app.models import User

PUBLIC_EXACT = {
    "/login",
    "/logout",
    "/api/health",
    "/api/auth/login",
    "/docs",
    "/openapi.json",
    "/redoc",
}

PUBLIC_PREFIXES = (
    "/static/",
)


def _normalize_path(path: str) -> str:
    if len(path) > 1:
        path = path.rstrip("/")
    return path


def _is_public_path(path: str) -> bool:
    path = _normalize_path(path)
    if path in PUBLIC_EXACT:
        return True
    return any(path.startswith(prefix) for prefix in PUBLIC_PREFIXES)


def _load_user_from_session(request: Request) -> User | None:
    user_id = request.session.get("user_id")
    if not user_id:
        return None
    db = SessionLocal()
    try:
        return get_user_by_id(db, int(user_id))
    finally:
        db.close()


class AuthMiddleware(BaseHTTPMiddleware):
    """Exige sessão autenticada nas rotas do dashboard e da API (exceto públicas)."""

    async def dispatch(self, request: Request, call_next):
        path = _normalize_path(request.url.path)

        if _is_public_path(path):
            request.state.user = _load_user_from_session(request)
            return await call_next(request)

        # Upload: aceita sessão opcional (app autenticado → user; legado → admin).
        if path == "/api/runs/upload" and request.method == "POST":
            request.state.user = _load_user_from_session(request)
            return await call_next(request)

        if path == "/api/auth/login" and request.method == "POST":
            request.state.user = None
            return await call_next(request)

        if path == "/api/auth/logout" and request.method == "POST":
            request.state.user = _load_user_from_session(request)
            return await call_next(request)

        user = _load_user_from_session(request)
        request.state.user = user

        if user is not None:
            return await call_next(request)

        if path.startswith("/api/"):
            ua = request.headers.get("user-agent", "-")
            boot = request.headers.get("x-kinexa-boot", "-")
            logging.getLogger("kinexa.auth").warning(
                "401 %s %s ua=%s boot=%s",
                request.method,
                path,
                ua,
                boot,
            )
            return JSONResponse(
                status_code=401,
                content={"detail": "Autenticação necessária."},
            )

        next_url = quote(path)
        error = request.query_params.get("error")
        login_url = f"/login?next={next_url}"
        if error:
            login_url = f"{login_url}&error={quote(error)}"
        return RedirectResponse(url=login_url, status_code=303)


def get_current_user(request: Request) -> User:
    user = getattr(request.state, "user", None)
    if user is None:
        if request.url.path.startswith("/api/"):
            raise HTTPException(status_code=401, detail="Autenticação necessária.")
        raise HTTPException(status_code=303, headers={"Location": "/login"})
    return user


def get_current_user_dep(request: Request) -> User:
    return get_current_user(request)


CurrentUser = Depends(get_current_user_dep)


def get_optional_user(request: Request) -> User | None:
    return getattr(request.state, "user", None)
