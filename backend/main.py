from fastapi import Depends, FastAPI, HTTPException
from sqlalchemy.orm import Session

from database import create_tables, get_db
from models import Notification, User, UserSettings
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
from routers.notifications import router as notifications_router
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
    NewsArticle,
    ExchangeRate,
)

create_tables()

app = FastAPI()

app.include_router(transactions_router)
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

    user = User(
        email=data.email,
        password_hash=hash_password(data.password),
        name=data.name,
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

@app.get("/auth/me")
def get_me(current_user: User = Depends(get_current_user)):
    return {
        "id": current_user.id,
        "email": current_user.email,
        "name": current_user.name,
    }
