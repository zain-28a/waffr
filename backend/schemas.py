from pydantic import BaseModel, EmailStr, Field, field_validator


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str
    name: str | None = Field(default=None, max_length=100)
    gender: str | None = Field(default=None, max_length=20)
    birthdate: str | None = Field(default=None, max_length=40)
    country: str | None = Field(default=None, max_length=80)
    city: str | None = Field(default=None, max_length=80)
    street: str | None = Field(default=None, max_length=160)

    @field_validator(
        "name",
        "gender",
        "birthdate",
        "country",
        "city",
        "street",
        mode="before",
    )
    @classmethod
    def _blank_to_none(cls, value):
        if value is None:
            return None
        if isinstance(value, str):
            trimmed = value.strip()
            return trimmed or None
        return value

    @field_validator("gender")
    @classmethod
    def _known_gender(cls, value):
        if value is None:
            return None
        if value not in {"male", "female"}:
            raise ValueError("gender must be male or female")
        return value


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class AuthResponse(BaseModel):
    access_token: str
    token_type: str


class DataKeyIn(BaseModel):
    salt: str = Field(min_length=16, max_length=64)
    iterations: int = Field(ge=100_000, le=10_000_000)
    wrapped_key: str = Field(min_length=40, max_length=512)
