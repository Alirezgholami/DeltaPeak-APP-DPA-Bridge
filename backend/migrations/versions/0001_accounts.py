"""Initial DPA account and security tables.

Revision ID: 0001_accounts
Revises: None
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0001_accounts"
down_revision: Union[str, Sequence[str], None] = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("display_name", sa.String(length=120), nullable=False),
        sa.Column("mobile", sa.String(length=20), nullable=False),
        sa.Column("username", sa.String(length=20), nullable=False),
        sa.Column("email", sa.String(length=254), nullable=True),
        sa.Column("password_hash", sa.Text(), nullable=False),
        sa.Column("role", sa.String(length=16), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("auth_version", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_login_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_activity_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("mobile"),
        sa.UniqueConstraint("username"),
    )
    for col in ["mobile", "username", "role", "status", "created_at", "last_login_at", "last_activity_at"]:
        op.create_index(f"ix_users_{col}", "users", [col])

    op.create_table(
        "otp_challenges",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("mobile", sa.String(length=20), nullable=False),
        sa.Column("purpose", sa.String(length=32), nullable=False),
        sa.Column("code_hash", sa.String(length=64), nullable=False),
        sa.Column("request_ip", sa.String(length=64), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("resend_after_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("attempts_remaining", sa.Integer(), nullable=False),
        sa.Column("consumed_at", sa.DateTime(timezone=True), nullable=True),
    )
    for col in ["mobile", "purpose", "request_ip", "created_at", "expires_at"]:
        op.create_index(f"ix_otp_challenges_{col}", "otp_challenges", [col])
    op.create_index("ix_otp_mobile_created", "otp_challenges", ["mobile", "created_at"])
    op.create_index("ix_otp_ip_created", "otp_challenges", ["request_ip", "created_at"])

    op.create_table(
        "refresh_sessions",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("user_id", sa.String(length=36), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("token_hash"),
    )
    for col in ["user_id", "token_hash", "expires_at"]:
        op.create_index(f"ix_refresh_sessions_{col}", "refresh_sessions", [col])

    op.create_table(
        "revoked_access_tokens",
        sa.Column("jti", sa.String(length=64), primary_key=True),
        sa.Column("user_id", sa.String(length=36), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=False),
    )
    for col in ["user_id", "expires_at"]:
        op.create_index(f"ix_revoked_access_tokens_{col}", "revoked_access_tokens", [col])

    op.create_table(
        "audit_logs",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("actor_user_id", sa.String(length=36), nullable=True),
        sa.Column("action", sa.String(length=80), nullable=False),
        sa.Column("target_type", sa.String(length=40), nullable=True),
        sa.Column("target_id", sa.String(length=80), nullable=True),
        sa.Column("request_ip", sa.String(length=64), nullable=False),
        sa.Column("details", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    for col in ["actor_user_id", "action", "created_at"]:
        op.create_index(f"ix_audit_logs_{col}", "audit_logs", [col])


def downgrade() -> None:
    op.drop_table("audit_logs")
    op.drop_table("revoked_access_tokens")
    op.drop_table("refresh_sessions")
    op.drop_table("otp_challenges")
    op.drop_table("users")
