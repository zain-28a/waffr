import asyncio
from contextlib import asynccontextmanager, suppress

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from database import create_tables, get_db, utc_now
from category_model import ExpenseCategory
from models import Notification, User, UserSettings
from preset_model import ExpensePreset
import password_reset
import profile_photo as stored_photo
from schemas import (
    AuthResponse,
    ChangePasswordRequest,
    DataKeyIn,
    ForgotPasswordRequest,
    LoginRequest,
    RegisterRequest,
    ResetPasswordRequest,
)
from auth import (
    hash_password,
    verify_password,
    create_access_token,
    get_current_user,
)
from goal_model import SavingsGoal, SavingsTransfer
from online_model import ExchangeRate, NewsArticle
from shopping_model import ShoppingItem, ShoppingList
from transaction_model import RecurringExpense, Transaction
from news_service import news_refresh_loop
from routers.ai import router as ai_router
from routers.notifications import router as notifications_router
from routers.online import router as online_router
from routers.recurring import router as recurring_router
from routers.savings import router as savings_router
from routers.settings import router as settings_router
from routers.shopping import router as shopping_router
from routers.sync import router as sync_router
from routers.transactions import router as transactions_router

_MODEL_MODULES = (
    User,
    UserSettings,
    Notification,
    Transaction,
    RecurringExpense,
    SavingsGoal,
    SavingsTransfer,
    ShoppingList,
    ShoppingItem,
    ExpenseCategory,
    ExpensePreset,
    NewsArticle,
    ExchangeRate,
)

create_tables()


@asynccontextmanager
async def _lifespan(_app: FastAPI):
    task = asyncio.create_task(news_refresh_loop())
    try:
        yield
    finally:
        task.cancel()
        with suppress(asyncio.CancelledError):
            await task


app = FastAPI(lifespan=_lifespan)

app.include_router(transactions_router)
app.include_router(online_router)
app.include_router(savings_router)
app.include_router(shopping_router)
app.include_router(recurring_router)
app.include_router(notifications_router)
app.include_router(settings_router)
app.include_router(sync_router)
app.include_router(ai_router)


@app.get("/")
def root():
    return {"message": "Waffr API is running"}


@app.post("/auth/register", response_model=AuthResponse)
def register(data: RegisterRequest, db: Session = Depends(get_db)):
    existing_user = db.query(User).filter(User.email == data.email).first()

    if existing_user:
        raise HTTPException(
            status_code=400,
            detail="Email already registered",
        )

    name = _clean(data.name)
    gender = _clean(data.gender)
    birthdate = _clean(data.birthdate)
    country = _clean(data.country)
    city = _clean(data.city)
    street = _clean(data.street)
    phone = _clean(data.phone)

    user = User(
        email=data.email,
        password_hash=hash_password(data.password),
        name=name,
        gender=gender,
        birthdate=birthdate,
        country=country,
        city=city,
        street=street,
        phone=phone,
        settings=UserSettings(
            gender=gender,
            birthdate=birthdate,
            processed_period_keys=[],
        ),
    )

    db.add(user)
    db.commit()
    db.refresh(user)

    token = create_access_token(user)

    return {
        "access_token": token,
        "token_type": "bearer",
    }


@app.post("/auth/login", response_model=AuthResponse)
def login(data: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == data.email).first()

    if not user or not verify_password(data.password, user.password_hash):
        raise HTTPException(
            status_code=401,
            detail="Invalid email or password",
        )

    token = create_access_token(user)

    return {
        "access_token": token,
        "token_type": "bearer",
    }


def _clean(value: str | None) -> str | None:
    if value is None:
        return None
    trimmed = value.strip()
    return trimmed or None


def _profile_text(user: User, field: str, *, settings_fallback: bool = False) -> str | None:
    direct = _clean(getattr(user, field))
    if direct:
        return direct
    if not settings_fallback or user.settings is None:
        return None
    return _clean(getattr(user.settings, field, None))


def _photo_meta(user: User) -> dict:
    return {
        "has_photo": stored_photo.has_photo(user.id),
        "photo_updated_at": user.photo_updated_at,
    }


def _user_payload(user: User) -> dict:
    return {
        "id": user.id,
        "email": user.email,
        "name": _clean(user.name),
        "gender": _profile_text(user, "gender", settings_fallback=True),
        "birthdate": _profile_text(user, "birthdate", settings_fallback=True),
        "country": _clean(user.country),
        "city": _clean(user.city),
        "street": _clean(user.street),
        "phone": _clean(user.phone),
        "data_key": _data_key(user),
        **_photo_meta(user),
    }


def _data_key(user: User) -> dict | None:
    if not user.wrapped_key or not user.key_salt or not user.key_iterations:
        return None
    return {
        "salt": user.key_salt,
        "iterations": user.key_iterations,
        "wrapped_key": user.wrapped_key,
    }


@app.get("/auth/me")
def get_me(current_user: User = Depends(get_current_user)):
    return _user_payload(current_user)


@app.put("/auth/key")
def store_data_key(
    data: DataKeyIn,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    # Set once. Replacing it would leave the encrypted rows unreadable.
    if current_user.wrapped_key:
        raise HTTPException(status_code=409, detail="Data key already set")
    current_user.key_salt = data.salt
    current_user.key_iterations = data.iterations
    current_user.wrapped_key = data.wrapped_key
    db.commit()
    db.refresh(current_user)
    return {"data_key": _data_key(current_user)}


@app.post("/auth/password/forgot")
def forgot_password(data: ForgotPasswordRequest, db: Session = Depends(get_db)):
    if not password_reset.email_configured():
        raise HTTPException(status_code=503, detail="Email is not configured")
    # Same reply whether or not the email has an account.
    user = db.query(User).filter(User.email == data.email).first()
    if user is not None:
        code = password_reset.issue_code(user, utc_now())
        if code is not None:
            db.commit()
            try:
                password_reset.send_code(user.email, code)
            except password_reset.EmailSendFailed:
                raise HTTPException(
                    status_code=503,
                    detail="Could not send email",
                ) from None
    return {"ok": True}


@app.post("/auth/password/reset")
def reset_password(data: ResetPasswordRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == data.email).first()
    if user is None or not password_reset.check_code(user, data.code, utc_now()):
        db.commit()
        raise HTTPException(status_code=400, detail="Invalid or expired code")

    user.password_hash = hash_password(data.new_password)
    user.token_version += 1
    password_reset.clear_code(user)
    # The data key was wrapped with the old password and cannot be recovered.
    # The next sign-in creates a new one.
    user.key_salt = None
    user.key_iterations = None
    user.wrapped_key = None
    password_reset.drop_sealed_text(db, user.id)
    db.commit()
    return {"ok": True}


@app.post("/auth/password/change", response_model=AuthResponse)
def change_password(
    data: ChangePasswordRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if not verify_password(data.current_password, current_user.password_hash):
        raise HTTPException(status_code=400, detail="Current password is incorrect")
    if current_user.wrapped_key and data.data_key is None:
        raise HTTPException(status_code=400, detail="Data key is required")

    current_user.password_hash = hash_password(data.new_password)
    current_user.token_version += 1
    if data.data_key is not None:
        current_user.key_salt = data.data_key.salt
        current_user.key_iterations = data.data_key.iterations
        current_user.wrapped_key = data.data_key.wrapped_key
    db.commit()
    db.refresh(current_user)
    return {
        "access_token": create_access_token(current_user),
        "token_type": "bearer",
    }


@app.delete("/auth/account", status_code=204)
def delete_account(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    # Rows owned by the user go with it (ORM cascade and ON DELETE CASCADE).
    stored_photo.delete_photo(current_user.id)
    db.delete(current_user)
    db.commit()


@app.put("/auth/photo")
async def upload_photo(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    data = await request.body()
    if not data:
        raise HTTPException(status_code=400, detail="Image is required")
    try:
        stored_photo.save_photo(current_user.id, data)
    except ValueError as error:
        detail = "Image is too large" if str(error) == "image too large" else "Unsupported image"
        status = 413 if str(error) == "image too large" else 400
        raise HTTPException(status_code=status, detail=detail) from error

    current_user.photo_updated_at = utc_now()
    db.commit()
    db.refresh(current_user)
    return _photo_meta(current_user)


@app.get("/auth/photo")
def download_photo(current_user: User = Depends(get_current_user)):
    path = stored_photo.photo_path(current_user.id)
    if path is None:
        raise HTTPException(status_code=404, detail="No profile photo")
    return FileResponse(
        str(path),
        media_type=stored_photo.media_type_for(path),
        filename=path.name,
        headers={"Cache-Control": "no-store"},
    )


@app.delete("/auth/photo")
def delete_photo(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    stored_photo.delete_photo(current_user.id)
    current_user.photo_updated_at = utc_now()
    db.commit()
    db.refresh(current_user)
    return _photo_meta(current_user)
