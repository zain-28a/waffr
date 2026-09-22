import asyncio
from contextlib import asynccontextmanager, suppress

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from database import create_tables, get_db, utc_now
from category_model import ExpenseCategory
from models import Notification, User, UserSettings
import profile_photo as stored_photo
from schemas import RegisterRequest, LoginRequest, AuthResponse
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


@app.get("/")
def root():
    return {"message": "Waffer API is running"}


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

    user = User(
        email=data.email,
        password_hash=hash_password(data.password),
        name=name,
        gender=gender,
        birthdate=birthdate,
        country=country,
        city=city,
        street=street,
        settings=UserSettings(
            gender=gender,
            birthdate=birthdate,
            processed_period_keys=[],
        ),
    )

    db.add(user)
    db.commit()
    db.refresh(user)

    token = create_access_token(user.id)

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

    token = create_access_token(user.id)

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
        **_photo_meta(user),
    }


@app.get("/auth/me")
def get_me(current_user: User = Depends(get_current_user)):
    return _user_payload(current_user)


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
