"""Fetch, filter, and store SANA economic news.

The official feed is the general SANA RSS document, not an economy-only feed.
Section metadata is preferred over keyword matching:

* RSS ``category`` terms such as ``اقتصاد`` and ``اقتصاد سوريا``
* the article permalink section, such as ``/economy/``

``ECONOMY_KEYWORDS`` is used only when an entry has neither category tags nor
a permalink section.
"""

from __future__ import annotations

import asyncio
import calendar
import html
import logging
import re
import threading
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from urllib.parse import urlparse

import feedparser
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from database import SessionLocal, utc_now
from online_model import NewsArticle

logger = logging.getLogger("waffer.news")

SANA_FEED_URL = "https://sana.sy/feed/"
SOURCE_NAME = "sana.sy"
ALLOWED_HOSTS = frozenset({"sana.sy", "www.sana.sy"})
FEED_TIMEOUT_SECONDS = 20
MAX_FEED_BYTES = 2_000_000
NEWS_LIST_LIMIT = 30
NEWS_REFRESH_INTERVAL_SECONDS = 60 * 60
TITLE_LIMIT = 500
URL_LIMIT = 1000
GUID_LIMIT = 1000
SUMMARY_LIMIT = 4000

# Explicit SANA section names seen on the general RSS feed.
ECONOMY_CATEGORIES = frozenset({"اقتصاد", "اقتصاد سوريا"})

# First permalink segment for the economy desk, including child sections
# such as /economy/syrian-economy/.
ECONOMY_SECTION_SLUGS = frozenset({"economy"})

# Fallback only. Edit this tuple when category metadata is missing.
ECONOMY_KEYWORDS = (
    "اقتصاد",
    "مالي",
    "مالية",
    "مصرف",
    "سعر الصرف",
    "الليرة السورية",
    "التضخم",
    "ميزانية",
    "ضريبة",
    "البورصة",
    "استثمار",
    "جمارك",
    "النفط",
    "رواتب",
)

_TAG_RE = re.compile(r"<[^>]*>")
_WS_RE = re.compile(r"\s+")
_BIDI_RE = re.compile(
    r"[\u00ad\u200b-\u200f\u202a-\u202e\u2066-\u2069\ufeff\u0640]"
)
_refresh_lock = threading.Lock()


class NewsFeedUnavailable(Exception):
    """The upstream feed could not be fetched or parsed."""


@dataclass(frozen=True)
class NewsRefreshResult:
    ok: bool
    fetched: int = 0
    matched: int = 0
    saved: int = 0
    error: str | None = None


@dataclass(frozen=True)
class NormalizedArticle:
    title: str
    url: str
    guid: str
    summary: str | None
    published_at: datetime | None


_last_result = NewsRefreshResult(ok=False, error="not_run")


def clean_text(value: object, limit: int) -> str:
    if value is None:
        return ""
    text = html.unescape(str(value))
    text = _TAG_RE.sub(" ", text)
    text = _BIDI_RE.sub("", text)
    text = _WS_RE.sub(" ", text).strip()
    if len(text) > limit:
        return text[:limit].rstrip()
    return text


def _normalize(value: object) -> str:
    return clean_text(value, 300).casefold()


_ECONOMY_CATEGORY_KEYS = frozenset(_normalize(name) for name in ECONOMY_CATEGORIES)
_ECONOMY_KEYWORD_KEYS = tuple(_normalize(keyword) for keyword in ECONOMY_KEYWORDS)


def section_slug(url: str) -> str:
    path = urlparse(url).path.strip("/")
    if not path:
        return ""
    return path.split("/", 1)[0].casefold()


def is_economy_entry(
    categories: list[str],
    url: str,
    title: str,
    summary: str,
) -> bool:
    """Keep an entry when SANA marks it as economy.

    Category terms and the permalink section win. Keywords are consulted only
    when both of those signals are absent, so a political story that merely
    mentions money is not treated as economic news.
    """
    category_set = {_normalize(name) for name in categories if name}
    if category_set & _ECONOMY_CATEGORY_KEYS:
        return True
    section = section_slug(url)
    if section in ECONOMY_SECTION_SLUGS:
        return True
    if category_set or section:
        return False
    haystack = _normalize(f"{title} {summary}")
    return any(keyword and keyword in haystack for keyword in _ECONOMY_KEYWORD_KEYS)


def parse_published(entry: dict) -> datetime | None:
    parsed = entry.get("published_parsed") or entry.get("updated_parsed")
    if parsed:
        try:
            published = datetime.fromtimestamp(calendar.timegm(parsed), tz=timezone.utc)
        except (OverflowError, OSError, TypeError, ValueError):
            published = None
        else:
            if _plausible_year(published):
                return published

    raw = entry.get("published") or entry.get("updated") or ""
    if not raw:
        return None
    try:
        published = parsedate_to_datetime(str(raw))
    except (IndexError, OverflowError, TypeError, ValueError):
        return None
    if published.tzinfo is None:
        published = published.replace(tzinfo=timezone.utc)
    else:
        published = published.astimezone(timezone.utc)
    if not _plausible_year(published):
        return None
    return published


def _plausible_year(value: datetime) -> bool:
    year = value.year
    current = datetime.now(timezone.utc).year
    return 1990 <= year <= current + 1


def _entry_categories(entry: dict) -> list[str]:
    names: list[str] = []
    for tag in entry.get("tags") or []:
        term = ""
        if isinstance(tag, dict):
            term = tag.get("term") or tag.get("label") or ""
        else:
            term = getattr(tag, "term", "") or ""
        cleaned = _normalize(term)
        if cleaned:
            names.append(cleaned)
    return names


def _clean_url(value: object) -> str:
    text = html.unescape(str(value or "")).strip()
    text = _BIDI_RE.sub("", text)
    text = _WS_RE.sub("", text)
    if not text or len(text) > URL_LIMIT:
        return ""
    parsed = urlparse(text)
    host = (parsed.hostname or "").lower()
    if parsed.scheme not in {"http", "https"} or host not in ALLOWED_HOSTS:
        return ""
    return text


def _clean_guid(value: object, fallback_url: str) -> str:
    text = clean_text(value, GUID_LIMIT + 1)
    if not text:
        text = fallback_url
    if not text or len(text) > GUID_LIMIT:
        return ""
    return text


def _entry_summary(entry: dict) -> str:
    summary = clean_text(entry.get("summary"), SUMMARY_LIMIT)
    if summary:
        return summary
    content = entry.get("content") or []
    if isinstance(content, list) and content:
        first = content[0]
        raw = first.get("value") if isinstance(first, dict) else ""
        return clean_text(raw, SUMMARY_LIMIT)
    return ""


def normalize_entry(entry: dict) -> NormalizedArticle | None:
    url = _clean_url(entry.get("link"))
    title = clean_text(entry.get("title"), TITLE_LIMIT)
    if not url or not title:
        return None
    guid = _clean_guid(entry.get("id") or entry.get("guid"), url)
    if not guid:
        return None
    summary = _entry_summary(entry)
    categories = _entry_categories(entry)
    if not is_economy_entry(categories, url, title, summary):
        return None
    return NormalizedArticle(
        title=title,
        url=url,
        guid=guid,
        summary=summary or None,
        published_at=parse_published(entry),
    )


def parse_feed(payload: bytes) -> tuple[int, list[NormalizedArticle]]:
    parsed = feedparser.parse(payload)
    entries = list(getattr(parsed, "entries", None) or [])
    if not entries and getattr(parsed, "bozo", False):
        raise NewsFeedUnavailable()
    articles: list[NormalizedArticle] = []
    seen: set[str] = set()
    for entry in entries:
        article = normalize_entry(entry)
        if article is None or article.guid in seen or article.url in seen:
            continue
        seen.add(article.guid)
        seen.add(article.url)
        articles.append(article)
    return len(entries), articles


def fetch_feed() -> bytes:
    request = urllib.request.Request(
        SANA_FEED_URL,
        headers={
            "User-Agent": "Waffer/1.0",
            "Accept": "application/rss+xml, application/xml, text/xml;q=0.9, */*;q=0.8",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=FEED_TIMEOUT_SECONDS) as response:
            final_host = (urlparse(response.geturl()).hostname or "").lower()
            if final_host not in ALLOWED_HOSTS:
                raise NewsFeedUnavailable()
            payload = response.read(MAX_FEED_BYTES + 1)
    except NewsFeedUnavailable:
        raise
    except (TimeoutError, urllib.error.URLError, OSError) as exc:
        logger.warning("SANA feed request failed: %s", type(exc).__name__)
        raise NewsFeedUnavailable() from exc
    if not payload or len(payload) > MAX_FEED_BYTES:
        raise NewsFeedUnavailable()
    return payload


def _query_latest(db: Session, limit: int) -> list[NewsArticle]:
    return (
        db.query(NewsArticle)
        .order_by(NewsArticle.published_at.desc(), NewsArticle.id.desc())
        .limit(limit)
        .all()
    )


def _taken(db: Session, column, value: str, row_id: int) -> bool:
    return (
        db.query(NewsArticle.id)
        .filter(column == value, NewsArticle.id != row_id)
        .first()
        is not None
    )


def _upsert(db: Session, article: NormalizedArticle, fetched_at: datetime) -> None:
    matches = (
        db.query(NewsArticle)
        .filter((NewsArticle.guid == article.guid) | (NewsArticle.url == article.url))
        .all()
    )
    existing = next((row for row in matches if row.guid == article.guid), None)
    if existing is None and matches:
        existing = matches[0]

    published_at = article.published_at
    if existing is None:
        db.add(
            NewsArticle(
                title=article.title,
                source=SOURCE_NAME,
                url=article.url,
                guid=article.guid,
                summary=article.summary,
                published_at=published_at or fetched_at,
                fetched_at=fetched_at,
            )
        )
        return

    existing.title = article.title
    existing.source = SOURCE_NAME
    existing.summary = article.summary
    existing.fetched_at = fetched_at
    if published_at is not None:
        existing.published_at = published_at
    if existing.guid != article.guid and not _taken(db, NewsArticle.guid, article.guid, existing.id):
        existing.guid = article.guid
    if existing.url != article.url and not _taken(db, NewsArticle.url, article.url, existing.id):
        existing.url = article.url


def _store_articles(db: Session, articles: list[NormalizedArticle]) -> int:
    fetched_at = utc_now()
    saved = 0
    for article in articles:
        try:
            with db.begin_nested():
                _upsert(db, article, fetched_at)
            saved += 1
        except IntegrityError:
            logger.warning("skipped news row that conflicted with an existing article")
    db.commit()
    return saved


def _refresh_unlocked() -> NewsRefreshResult:
    try:
        payload = fetch_feed()
        fetched, articles = parse_feed(payload)
    except NewsFeedUnavailable:
        logger.warning("SANA feed unavailable; previously stored news was kept")
        return NewsRefreshResult(ok=False, error="feed_unavailable")

    db = SessionLocal()
    try:
        saved = _store_articles(db, articles)
    except Exception:
        db.rollback()
        logger.exception("failed to store SANA news; previously stored news was kept")
        return NewsRefreshResult(
            ok=False,
            fetched=fetched,
            matched=len(articles),
            error="store_failed",
        )
    finally:
        db.close()

    logger.info(
        "SANA news refresh stored %s economic articles from %s feed entries",
        saved,
        fetched,
    )
    return NewsRefreshResult(
        ok=True,
        fetched=fetched,
        matched=len(articles),
        saved=saved,
    )


def refresh_news(*, wait: bool = True) -> NewsRefreshResult:
    """Fetch the RSS feed and upsert economic articles.

    A failed fetch leaves existing rows in place. Overlapping calls share one
    refresh so repeated triggers do not insert duplicates.
    """
    global _last_result
    acquired = _refresh_lock.acquire(blocking=False)
    if not acquired:
        if not wait:
            return _last_result
        _refresh_lock.acquire()
        _refresh_lock.release()
        return _last_result

    try:
        _last_result = _refresh_unlocked()
        return _last_result
    except Exception:
        logger.exception("SANA news refresh failed; previously stored news was kept")
        _last_result = NewsRefreshResult(ok=False, error="feed_unavailable")
        return _last_result
    finally:
        _refresh_lock.release()


def latest_articles(db: Session, limit: int = NEWS_LIST_LIMIT) -> list[NewsArticle]:
    """Return stored articles, filling the table once when it is empty."""
    bounded = max(1, min(limit, NEWS_LIST_LIMIT))
    existing = db.query(NewsArticle.id).limit(1).first()
    if existing is not None:
        return _query_latest(db, bounded)

    db.rollback()
    result = refresh_news(wait=True)
    rows = _query_latest(db, bounded)
    if not rows and not result.ok:
        raise NewsFeedUnavailable()
    return rows


async def news_refresh_loop() -> None:
    """Hourly refresh. There is no other scheduler in this project."""
    while True:
        await asyncio.to_thread(refresh_news, wait=False)
        await asyncio.sleep(NEWS_REFRESH_INTERVAL_SECONDS)
