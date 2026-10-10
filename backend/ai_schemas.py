"""Request and response bodies for /ai.

The app sends totals only (per category, per goal), never single
transactions, so the model sees the shape of spending and not the ledger.
"""

from typing import Literal

from pydantic import BaseModel, Field


class CategoryTotal(BaseModel):
    name: str = Field(max_length=60)
    current: float = Field(ge=0)
    previous: float = Field(ge=0)


class GoalSummary(BaseModel):
    name: str = Field(max_length=80)
    target: float = Field(ge=0)
    saved: float = Field(ge=0)


class ObligationSummary(BaseModel):
    name: str = Field(max_length=80)
    amount: float = Field(ge=0)
    frequency: str = Field(max_length=20)


class InsightsRequest(BaseModel):
    kind: Literal["weekly", "monthly"]
    currency: str = Field(max_length=12)
    period_label: str = Field(max_length=60)
    days_elapsed: int = Field(ge=0, le=31)
    days_total: int = Field(ge=1, le=31)
    monthly_income: float | None = Field(default=None, ge=0)
    balance: float
    cycle_spent: float = Field(ge=0)
    max_balance: float = Field(ge=0)
    days_until_income: int | None = Field(default=None, ge=0, le=62)
    total_saved: float = Field(default=0, ge=0)
    categories: list[CategoryTotal] = Field(default_factory=list, max_length=40)
    goals: list[GoalSummary] = Field(default_factory=list, max_length=20)
    obligations: list[ObligationSummary] = Field(
        default_factory=list, max_length=30
    )


class Insight(BaseModel):
    tone: Literal["warning", "positive", "tip"]
    title: str
    body: str


class SavingsSuggestion(BaseModel):
    monthly_amount: float
    reason: str


class InsightsResponse(BaseModel):
    headline: str
    insights: list[Insight]
    savings_suggestion: SavingsSuggestion | None
    summary: str


class CategorizeRequest(BaseModel):
    note: str = Field(min_length=2, max_length=200)
    categories: list[str] = Field(min_length=1, max_length=40)


class CategorizeResponse(BaseModel):
    category: str | None
