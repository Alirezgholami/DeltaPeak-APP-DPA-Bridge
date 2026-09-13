from __future__ import annotations

from pydantic import BaseModel, Field


class RegisterRequest(BaseModel):
    display_name: str = Field(min_length=1, max_length=120)
    mobile: str
    username: str | None = None
    password: str = Field(min_length=8, max_length=128)


class RegisterOtpRequest(BaseModel):
    mobile: str
    resend: bool = False


class RegisterConfirmRequest(BaseModel):
    display_name: str = Field(min_length=1, max_length=120)
    mobile: str
    code: str = Field(min_length=4, max_length=12)
    password: str = Field(min_length=8, max_length=128)


class LoginRequest(BaseModel):
    mobile: str | None = None
    username: str | None = None
    password: str = Field(min_length=1, max_length=128)


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str = Field(min_length=8, max_length=128)


class PasswordResetRequest(BaseModel):
    mobile: str
    resend: bool = False


class PasswordResetConfirm(BaseModel):
    mobile: str
    code: str = Field(min_length=4, max_length=12)
    new_password: str = Field(min_length=8, max_length=128)


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=20)
