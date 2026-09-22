from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from api_schemas import NewsArticleOut, NewsRefreshOut
from database import get_db
from news_service import NewsFeedUnavailable, latest_articles, refresh_news

router = APIRouter(prefix="/online", tags=["online"])


@router.get("/news", response_model=list[NewsArticleOut])
def list_news(db: Session = Depends(get_db)):
    try:
        return latest_articles(db)
    except NewsFeedUnavailable:
        raise HTTPException(
            status_code=503,
            detail="News is temporarily unavailable",
        ) from None


@router.post("/news/refresh", response_model=NewsRefreshOut)
def refresh_news_now():
    result = refresh_news(wait=True)
    return NewsRefreshOut(
        ok=result.ok,
        fetched=result.fetched,
        matched=result.matched,
        saved=result.saved,
        error=result.error,
    )
