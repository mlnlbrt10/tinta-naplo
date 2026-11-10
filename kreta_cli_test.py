#!/usr/bin/env python3
"""
Standalone E-Kréta API v3 Authentication & Data Retrieval CLI Test Script.

Mapped from `kreta_api` (`lib/src/endpoints.dart`, `lib/src/resp/token_grant.dart`,
`lib/src/exceptions/token.dart`, `lib/src/model/*`, `test/mock_kreta_server_test.dart`)
and its parent `firka` client (`KretaLoginEndpoints`, `KretaClient`).

Features:
1. Reads `KRETA_INSTITUTION_ID`, `KRETA_USERNAME`, and `KRETA_PASSWORD` from `.env`,
   environment variables, CLI flags, or interactive terminal prompts.
2. Executes the full IDP OAuth2 Authorization Code + PKCE flow (with optional
   `refresh_token` verification and legacy/mock `password` grant fallback).
3. Validates the retrieved Bearer `access_token` and `id_token` JWT claims.
4. Fetches today's timetable lessons (`/ellenorzo/v3/sajat/OrarendElemek`) and
   the 5 most recent student evaluations/grades (`/ellenorzo/v3/sajat/Ertekelesek`).
5. Outputs structured step-by-step logs and actionable diagnostics on failure
   (HTTP 400/401/403, CAPTCHA challenges, or header/client_id mismatches).
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import getpass
import hashlib
import hmac
import html
from html.parser import HTMLParser
import json
import os
import re
import secrets
import sys
import urllib.parse
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import requests


# ============================================================================
# 1. Constants & Endpoints (mapped from kreta_api & firka_common/consts.dart)
# ============================================================================

class KretaConstants:
    """Authentication and client constants used by Firka / Kréta Mobile v3."""

    IDP_BASE = "https://idp.e-kreta.hu"
    KRETA_BASE = "e-kreta.hu"

    # Client IDs (from firka_common/lib/core/consts.dart)
    CLIENT_ID_IOS = "kreta-ellenorzo-student-mobile-ios"
    CLIENT_ID_ANDROID = "kreta-ellenorzo-student-mobile-android"
    CLIENT_ID_LEGACY = "kreta-ellenorzo-mobile-android"

    # Registered mobile OAuth2 callback URI
    REDIRECT_URI = "https://mobil.e-kreta.hu/ellenorzo-student/prod/oauthredirect"

    # OAuth2 / OIDC Scopes
    SCOPES = (
        "openid email offline_access "
        "kreta-ellenorzo-webapi.public "
        "kreta-eugyintezes-webapi.public "
        "kreta-fileservice-webapi.public "
        "kreta-mobile-global-webapi.public "
        "kreta-dkt-webapi.public "
        "kreta-ier-webapi.public"
    )

    # Required custom headers (from firka/lib/app/app_state.dart & kreta_client.dart)
    USER_AGENT_IOS = "eKretaStudent/264745 CFNetwork/1494.0.7 Darwin/23.4.0"
    USER_AGENT_ANDROID = "hu.ekreta.student/5.15.0/SM-G991B/13/33"
    API_KEY = "21ff6c25-d1da-4a68-a811-c881a6057463"

    # Legacy v2/v3 HMAC key for /nonce + X-AuthorizationPolicy-Key ("baSsxOwlU1jM")
    LEGACY_HMAC_KEY = bytes([98, 97, 83, 115, 120, 79, 119, 108, 85, 49, 106, 77])


class KretaEndpoints:
    """URL builders mapped 1:1 from `kreta_api/lib/src/endpoints.dart`."""

    @staticmethod
    def kreta(iss: str, mock_base_url: str | None = None) -> str:
        if mock_base_url:
            return mock_base_url.rstrip("/")
        if iss == "firka-test":
            return f"https://{KretaConstants.KRETA_BASE}"
        return f"https://{iss}.{KretaConstants.KRETA_BASE}"

    @staticmethod
    def idp(mock_base_url: str | None = None) -> str:
        if mock_base_url:
            return mock_base_url.rstrip("/")
        return KretaConstants.IDP_BASE

    @staticmethod
    def date_query(
        from_date: dt.date | dt.datetime | None = None,
        to_date: dt.date | dt.datetime | None = None,
    ) -> str:
        if from_date is None:
            if to_date is None:
                return ""
            raise ValueError("'from_date' is required to use 'to_date'")
        q = f"?datumTol={from_date.strftime('%Y-%m-%d')}"
        if to_date is not None:
            q += f"&datumIg={to_date.strftime('%Y-%m-%d')}"
        return q

    @classmethod
    def get_student(cls, iss: str, mock_base: str | None = None) -> str:
        return f"{cls.kreta(iss, mock_base)}/ellenorzo/v3/sajat/TanuloAdatlap"

    @classmethod
    def get_grades(
        cls,
        iss: str,
        from_date: dt.date | None = None,
        to_date: dt.date | None = None,
        mock_base: str | None = None,
    ) -> str:
        return (
            f"{cls.kreta(iss, mock_base)}/ellenorzo/v3/sajat/Ertekelesek"
            f"{cls.date_query(from_date, to_date)}"
        )

    @classmethod
    def get_timetable(
        cls,
        iss: str,
        from_date: dt.date | None = None,
        to_date: dt.date | None = None,
        mock_base: str | None = None,
    ) -> str:
        return (
            f"{cls.kreta(iss, mock_base)}/ellenorzo/v3/sajat/OrarendElemek"
            f"{cls.date_query(from_date, to_date)}"
        )

    @classmethod
    def get_omissions(
        cls,
        iss: str,
        from_date: dt.date | None = None,
        to_date: dt.date | None = None,
        mock_base: str | None = None,
    ) -> str:
        return (
            f"{cls.kreta(iss, mock_base)}/ellenorzo/v3/sajat/Mulasztasok"
            f"{cls.date_query(from_date, to_date)}"
        )


# ============================================================================
# 2. DTOs & Exceptions (mapped from kreta_api/lib/src/resp & exceptions)
# ============================================================================

class TokenExpiredException(Exception):
    """Mapped from `kreta_api/lib/src/exceptions/token.dart` (HTTP 400 on refresh)."""


class InvalidGrantException(Exception):
    """Mapped from `kreta_api/lib/src/exceptions/token.dart` (HTTP 401 on grant/refresh)."""


@dataclass
class TokenGrantResponse:
    """Mapped from `kreta_api/lib/src/resp/token_grant.dart`."""

    id_token: str
    access_token: str
    expires_in: int
    token_type: str
    refresh_token: str
    scope: str

    @classmethod
    def from_json(cls, data: dict[str, Any]) -> "TokenGrantResponse":
        return cls(
            id_token=data.get("id_token", ""),
            access_token=data["access_token"],
            expires_in=int(data.get("expires_in", 1800)),
            token_type=data.get("token_type", "Bearer"),
            refresh_token=data.get("refresh_token", ""),
            scope=data.get("scope", ""),
        )


# ============================================================================
# 3. Structured Logger & Diagnostic Helper
# ============================================================================

class StepLogger:
    """Structured console logger for CLI steps and error diagnostics."""

    RESET = "\033[0m"
    BOLD = "\033[1m"
    CYAN = "\033[36m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    RED = "\033[31m"

    def __init__(self, use_color: bool = True) -> None:
        self.use_color = use_color and sys.stdout.isatty()

    def _fmt(self, color: str, text: str) -> str:
        return f"{color}{text}{self.RESET}" if self.use_color else text

    def step(self, step_num: int, total: int, title: str) -> None:
        banner = f"[STEP {step_num}/{total}] {title}"
        print(f"\n{self._fmt(self.BOLD + self.CYAN, banner)}")
        print("-" * len(banner))

    def info(self, msg: str) -> None:
        print(f"  {self._fmt(self.CYAN, 'INFO')}  {msg}")

    def ok(self, msg: str) -> None:
        print(f"  {self._fmt(self.GREEN, 'PASS')}  {msg}")

    def warn(self, msg: str) -> None:
        print(f"  {self._fmt(self.YELLOW, 'WARN')}  {msg}")

    def fail(self, msg: str) -> None:
        print(f"  {self._fmt(self.RED, 'FAIL')}  {msg}")

    def diagnose_failure(
        self,
        context: str,
        status_code: int | None,
        response_text: str,
        request_headers: dict[str, str] | None = None,
    ) -> None:
        """Prints actionable debugging details for HTTP 400/401/403, CAPTCHA, or header mismatches."""
        print(f"\n  {self._fmt(self.BOLD + self.RED, '=== DIAGNOSTIC REPORT ===')}")
        print(f"  Context     : {context}")
        print(f"  HTTP Status : {status_code if status_code is not None else 'N/A (Network/Parse Error)'}")

        lower_body = (response_text or "").lower()

        # Check for active CAPTCHA / anti-bot gates (ignore passive recaptcha/api.js script tag)
        if any(marker in lower_body for marker in ("g-recaptcha", "cf-turnstile", "data-sitekey")):
            print("  Root Cause  : CAPTCHA / Anti-Bot Challenge Detected on IDP Login Page.")
            print("  Actionable Fix:")
            print("    - E-Kréta IDP (`idp.e-kreta.hu`) triggered a CAPTCHA challenge (often after repeated")
            print("      automated login attempts or missing browser cookies).")
            print("    - Do NOT attempt automated CAPTCHA bypassing. Instead, complete login once in a browser")
            print("      or Firka's WebView and pass the resulting OAuth redirect `code` via `--auth-code <CODE>`,")
            print("      or wait for the IDP rate-limit cooldown before retrying.")

        elif status_code == 400:
            print("  Root Cause  : HTTP 400 Bad Request (OAuth2 Grant / Parameter / Date Query Error).")
            if "invalid_grant" in lower_body:
                print("  Actionable Fix:")
                print("    - Maps to `TokenExpiredException` in `kreta_api`.")
                print("    - The authorization `code` or `refresh_token` is expired, already redeemed, or")
                print("      the PKCE `code_verifier` did not match the initial `code_challenge`.")
            elif "invalid_client" in lower_body or "unauthorized_client" in lower_body:
                print("  Actionable Fix:")
                print(f"    - Verify `client_id` is `{KretaConstants.CLIENT_ID_IOS}` or `{KretaConstants.CLIENT_ID_ANDROID}`.")
                print(f"    - Verify `redirect_uri` is exactly `{KretaConstants.REDIRECT_URI}`.")
            else:
                print("  Actionable Fix:")
                print("    - Check `institute_code` (iss), `datumTol`/`datumIg` format (`yyyy-MM-dd`),")
                print("      and ensure `Content-Type: application/x-www-form-urlencoded; charset=UTF-8` is set.")

        elif status_code == 401:
            print("  Root Cause  : HTTP 401 Unauthorized (`InvalidGrantException` or Rejected Bearer Token).")
            print("  Actionable Fix:")
            print("    - Check that `KRETA_USERNAME`, `KRETA_PASSWORD`, and `KRETA_INSTITUTION_ID` are valid.")
            print("    - Ensure `Authorization: Bearer <access_token>` is present on `/ellenorzo/v3/sajat/*` calls.")
            print("    - Ensure the institution subdomain (`https://<iss>.e-kreta.hu`) matches the")
            print("      `kreta:institute_code` claim inside the JWT access token.")

        elif status_code == 403:
            print("  Root Cause  : HTTP 403 Forbidden (Header Mismatch, Missing apiKey, or WAF Block).")
            print("  Actionable Fix:")
            print(f"    - Verify `User-Agent` header is set to `{KretaConstants.USER_AGENT_IOS}`")
            print("      (default `python-requests/*` User-Agent is blocked by Kréta servers).")
            print(f"    - Verify `apiKey: {KretaConstants.API_KEY}` header is included on API requests.")
            if request_headers:
                ua = request_headers.get("user-agent") or request_headers.get("User-Agent")
                ak = request_headers.get("apiKey")
                print(f"    - Sent User-Agent : {ua!r}")
                print(f"    - Sent apiKey     : {ak!r}")

        else:
            print("  Root Cause  : Unexpected HTTP / Transport Failure.")
            print("  Actionable Fix:")
            print("    - Verify institution ID (`iss`) resolves to `https://<iss>.e-kreta.hu`.")
            print("    - Note: Timetable queries (`OrarendElemek`) spanning >30 days may fail on Kréta v3.")

        snippet = (response_text or "").strip()
        if snippet:
            preview = snippet[:400] + ("..." if len(snippet) > 400 else "")
            print(f"  Response Body Preview:\n    {preview}")
        print(f"  {self._fmt(self.BOLD + self.RED, '=========================')}\n")


# ============================================================================
# 4. PKCE, JWT, and .env Utilities
# ============================================================================

def load_dotenv_file(dotenv_path: Path) -> dict[str, str]:
    """Minimal .env parser requiring no external packages."""
    values: dict[str, str] = {}
    if not dotenv_path.is_file():
        return values
    for raw_line in dotenv_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        key = key.strip()
        val = val.strip().strip("'").strip('"')
        values[key] = val
    return values


def generate_pkce_pair() -> tuple[str, str, str]:
    """
    Generates `(code_verifier, code_challenge, state_or_nonce)` matching
    `KretaLoginEndpoints` in `firka_common/lib/core/consts.dart`.
    """
    verifier_bytes = secrets.token_bytes(32)
    code_verifier = base64.urlsafe_b64encode(verifier_bytes).decode("ascii").rstrip("=")

    digest = hashlib.sha256(code_verifier.encode("ascii")).digest()
    code_challenge = base64.urlsafe_b64encode(digest).decode("ascii").rstrip("=")

    nonce_bytes = secrets.token_bytes(16)
    state_or_nonce = base64.urlsafe_b64encode(nonce_bytes).decode("ascii").rstrip("=")
    return code_verifier, code_challenge, state_or_nonce


def decode_jwt_payload(token: str) -> dict[str, Any]:
    """Decodes a JWT payload segment without external dependencies."""
    parts = token.split(".")
    if len(parts) < 2:
        raise ValueError("Token is not a valid 3-part JWT")
    payload_b64 = parts[1]
    padding = "=" * (-len(payload_b64) % 4)
    decoded = base64.urlsafe_b64decode(payload_b64 + padding).decode("utf-8")
    return json.loads(decoded)


class _LoginFormHTMLParser(HTMLParser):
    """Parses the primary login <form> from GET /Account/Login to inspect <input> and <select> fields."""

    def __init__(self) -> None:
        super().__init__()
        self.in_login_form = False
        self.form_index = 0
        self.form_attrs: dict[str, str] = {}
        self.fields: list[dict[str, str]] = []
        self._current_select: dict[str, str] | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attr_map = {k: (v if v is not None else "") for k, v in attrs}
        if tag == "form":
            self.form_index += 1
            if self.form_index == 1 or "loading-form" in attr_map.get("class", ""):
                self.in_login_form = True
                self.form_attrs = attr_map
        elif self.in_login_form and tag == "input":
            self.fields.append(
                {
                    "tag": "input",
                    "name": attr_map.get("name", ""),
                    "id": attr_map.get("id", ""),
                    "type": attr_map.get("type", "text"),
                    "value": attr_map.get("value", ""),
                    "placeholder": attr_map.get("placeholder", ""),
                }
            )
        elif self.in_login_form and tag == "select":
            self._current_select = {
                "tag": "select",
                "name": attr_map.get("name", ""),
                "id": attr_map.get("id", ""),
                "type": "select",
                "value": "",
                "placeholder": "",
            }
            self.fields.append(self._current_select)
        elif self.in_login_form and tag == "option" and self._current_select is not None:
            if "selected" in attr_map or not self._current_select["value"]:
                self._current_select["value"] = attr_map.get("value", "")

    def handle_endtag(self, tag: str) -> None:
        if tag == "form" and self.in_login_form:
            self.in_login_form = False
        elif tag == "select":
            self._current_select = None


def inspect_login_form_html(html_text: str, logger: StepLogger) -> list[dict[str, str]]:
    """
    Parses the GET /Account/Login HTML response, prints all <input> (and <select>)
    field names, types, and default/hidden values, and verifies how `InstituteCode`
    and `UserName` are represented on the form.
    """
    parser = _LoginFormHTMLParser()
    parser.feed(html_text)

    form_action = parser.form_attrs.get("action", "/Account/Login")
    logger.info(f"Parsed login <form> (action={form_action[:65]}{'...' if len(form_action) > 65 else ''}):")
    print("  Login Form Fields (<input> / <select>):")
    for idx, f in enumerate(parser.fields, start=1):
        name_disp = f["name"] or f"<unnamed id={f['id']}>"
        val_disp = f["value"]
        if len(val_disp) > 55:
            val_disp = val_disp[:52] + "..."
        extra = f" (placeholder={f['placeholder']!r})" if f["placeholder"] else ""
        print(
            f"    {idx}. tag=<{f['tag']}> name={name_disp!r} type={f['type']!r} value={val_disp!r}{extra}"
        )

    field_names = {f["name"]: f for f in parser.fields if f["name"]}
    inst_field = field_names.get("InstituteCode")
    user_field = field_names.get("UserName")

    if inst_field:
        logger.ok(
            f"Form verification: 'InstituteCode' IS present as a dedicated field "
            f"(<{inst_field['tag']} name='InstituteCode' type={inst_field['type']!r} "
            f"value={inst_field['value']!r}>)."
        )
    else:
        logger.warn("Form verification: 'InstituteCode' field was NOT found in login form.")

    if user_field:
        user_val = user_field.get("value", "")
        has_backslash = "\\" in user_val
        logger.ok(
            f"Form verification: 'UserName' (<input name='UserName' placeholder={user_field['placeholder']!r} "
            f"value={user_val!r}>) expects the plain student username (NOT 'institute\\username'; "
            f"contains backslash={has_backslash})."
        )

    return parser.fields


# ============================================================================
# 5. Kréta API Test Client
# ============================================================================

class KretaTestClient:
    """Minimal E-Kréta API v3 client implementing OAuth2 PKCE login, token refresh, and data queries."""

    def __init__(
        self,
        iss: str,
        username: str,
        password: str,
        logger: StepLogger,
        mock_base_url: str | None = None,
        client_id: str = KretaConstants.CLIENT_ID_IOS,
        user_agent: str = KretaConstants.USER_AGENT_IOS,
    ) -> None:
        self.iss = iss.strip()
        self.username = username.strip()
        self.password = password
        self.log = logger
        self.mock_base_url = mock_base_url
        self.client_id = client_id
        self.user_agent = user_agent
        self.session = requests.Session()
        self.token_grant: TokenGrantResponse | None = None

    def _idp_headers(self) -> dict[str, str]:
        return {
            "content-type": "application/x-www-form-urlencoded; charset=UTF-8",
            "accept": "*/*",
            "user-agent": self.user_agent,
        }

    def _api_headers(self) -> dict[str, str]:
        if not self.token_grant or not self.token_grant.access_token:
            raise RuntimeError("Cannot build API headers before authentication")
        return {
            "accept": "*/*",
            "user-agent": self.user_agent,
            "authorization": f"Bearer {self.token_grant.access_token}",
            "apiKey": KretaConstants.API_KEY,
        }

    def build_login_url(self, code_challenge: str, state_or_nonce: str) -> tuple[str, str]:
        """
        Builds the IDP `/Account/Login?ReturnUrl=...` URL matching
        `KretaLoginEndpoints.kretaLoginUrlRefresh` in `firka_common/lib/core/consts.dart`.
        Returns `(full_login_url, return_url_value)`.
        """
        idp_base = KretaEndpoints.idp(self.mock_base_url)
        callback_params = (
            f"redirect_uri={urllib.parse.quote(KretaConstants.REDIRECT_URI, safe='')}"
            f"&client_id={self.client_id}"
            f"&response_type=code"
            f"&login_hint={urllib.parse.quote(self.username, safe='')}"
            f"&prompt=login"
            f"&state={state_or_nonce}"
            f"&nonce={state_or_nonce}"
            f"&scope={urllib.parse.quote(KretaConstants.SCOPES, safe='')}"
            f"&code_challenge={code_challenge}"
            f"&code_challenge_method=S256"
            f"&institute_code={urllib.parse.quote(self.iss, safe='')}"
            f"&suppressed_prompt=login"
        )
        return_url = f"/connect/authorize/callback?{callback_params}"
        encoded_return_url = urllib.parse.quote(return_url, safe="")
        login_url = f"{idp_base}/Account/Login?ReturnUrl={encoded_return_url}"
        return login_url, return_url

    def authenticate_pkce(self, manual_auth_code: str | None = None) -> TokenGrantResponse:
        """
        Executes the full OAuth2 Authorization Code + PKCE authentication flow:
        1. GET `/Account/Login?ReturnUrl=...`
        2. Submit credentials (or read mock code) to obtain `code` from `oauthredirect`
        3. POST `/connect/token` (`grant_type=authorization_code`)
        """
        code_verifier, code_challenge, state_or_nonce = generate_pkce_pair()
        login_url, return_url = self.build_login_url(code_challenge, state_or_nonce)

        self.log.info(f"IDP Base URL      : {KretaEndpoints.idp(self.mock_base_url)}")
        self.log.info(f"Client ID         : {self.client_id}")
        self.log.info(f"User-Agent        : {self.user_agent}")
        self.log.info(f"PKCE Challenge    : {code_challenge[:16]}... (method=S256)")

        auth_code = manual_auth_code
        if not auth_code:
            self.log.info("Fetching IDP login page (GET /Account/Login)...")
            resp = self.session.get(
                login_url,
                headers={"User-Agent": self.user_agent, "Accept": "text/html,*/*"},
                timeout=20,
            )
            if resp.status_code != 200:
                self.log.diagnose_failure("GET /Account/Login", resp.status_code, resp.text)
                raise RuntimeError(f"GET /Account/Login failed with status {resp.status_code}")

            # Parse and print all <input> / <select> fields in the login form
            inspect_login_form_html(resp.text, self.log)

            # Case A: mock_kreta_server directly embeds `<input name="code" value="...">`
            # (see `kreta_api/test/mock_kreta_server_test.dart` lines 19-23)
            mock_code_match = re.search(r'name="code"\s+value="([^"]+)"', resp.text)
            if mock_code_match and "__RequestVerificationToken" not in resp.text:
                auth_code = mock_code_match.group(1)
                self.log.ok(f"Extracted authorization code from mock login page: {auth_code[:12]}...")
            else:
                # Check for active CAPTCHA challenge widget on the login page before submitting
                if any(k in resp.text.lower() for k in ("g-recaptcha", "cf-turnstile", "data-sitekey")):
                    self.log.diagnose_failure(
                        "GET /Account/Login (CAPTCHA present)", resp.status_code, resp.text
                    )
                    raise RuntimeError("CAPTCHA challenge detected on login page; aborting automated POST.")

                csrf_match = re.search(
                    r'name="__RequestVerificationToken"[^>]*value="([^"]+)"', resp.text
                )
                if not csrf_match:
                    self.log.diagnose_failure(
                        "Parse __RequestVerificationToken from /Account/Login",
                        resp.status_code,
                        resp.text,
                    )
                    raise RuntimeError("Could not find __RequestVerificationToken on login page.")

                csrf_token = html.unescape(csrf_match.group(1))
                self.log.ok(f"Retrieved CSRF __RequestVerificationToken ({len(csrf_token)} chars)")

                # Extract ReturnUrl from hidden form field if present
                ret_match = re.search(r'name="ReturnUrl"[^>]*value="([^"]+)"', resp.text)
                if ret_match:
                    return_url = html.unescape(ret_match.group(1))

                post_url = f"{KretaEndpoints.idp(self.mock_base_url)}/Account/Login"
                form_payload = {
                    "UserName": self.username,
                    "Password": self.password,
                    "InstituteCode": self.iss,
                    "ReturnUrl": return_url,
                    "__RequestVerificationToken": csrf_token,
                }

                self.log.info(
                    f"Session cookies preserved from GET: {list(self.session.cookies.keys())}"
                )
                self.log.info(
                    f"POST /Account/Login payload keys: {list(form_payload.keys())}"
                )
                print(f"  Payload dictionary keys: {list(form_payload.keys())}")
                self.log.info("Submitting credentials (POST /Account/Login)...")
                auth_code = self._submit_login_and_follow_callbacks(post_url, form_payload)

        return self.exchange_code_for_token(auth_code, code_verifier)

    def _submit_login_and_follow_callbacks(
        self, post_url: str, form_payload: dict[str, str]
    ) -> str:
        """
        Submits the login form and follows internal IDP redirects (`/connect/authorize/callback`)
        until reaching `https://mobil.e-kreta.hu/ellenorzo-student/prod/oauthredirect?code=...`.
        """
        req = requests.Request(
            "POST",
            post_url,
            data=form_payload,
            headers=self._idp_headers(),
        )
        prepared = self.session.prepare_request(req)
        raw_body = (
            prepared.body.decode("utf-8")
            if isinstance(prepared.body, bytes)
            else str(prepared.body or "")
        )
        masked_body = re.sub(r"(^|&)Password=[^&]*", r"\1Password=***", raw_body)
        print(f"  Raw POST body (password masked): {masked_body}")

        resp = self.session.send(
            prepared,
            allow_redirects=False,
            timeout=20,
        )

        # Follow up to 5 hops manually so we intercept the mobile redirect_uri before network resolution
        hops = 0
        while resp.is_redirect and hops < 5:
            hops += 1
            location = resp.headers.get("Location", "")
            parsed = urllib.parse.urlparse(location)
            qs = urllib.parse.parse_qs(parsed.query)

            if "/ellenorzo-student/prod/oauthredirect" in parsed.path or "code" in qs:
                if "code" in qs and qs["code"]:
                    code = qs["code"][0]
                    self.log.ok(f"Intercepted oauthredirect authorization code: {code[:12]}...")
                    return code
                if "error" in qs:
                    err_msg = f"{qs.get('error')} - {qs.get('error_description')}"
                    self.log.diagnose_failure("OAuth2 Callback Redirect", resp.status_code, err_msg)
                    raise RuntimeError(f"OAuth2 redirect returned error: {err_msg}")

            next_url = urllib.parse.urljoin(resp.url, location)
            resp = self.session.get(
                next_url,
                headers={"User-Agent": self.user_agent, "Accept": "*/*"},
                allow_redirects=False,
                timeout=20,
            )

        # If we landed on a 200 HTML page, login likely failed (invalid credentials or CAPTCHA)
        val_err = re.findall(
            r'<div[^>]*validation-summary-errors[^>]*>(.*?)</div>',
            resp.text,
            flags=re.DOTALL | re.IGNORECASE,
        )
        cleaned_err = (
            re.sub(r"<[^>]+>", " ", " ".join(val_err)).strip() if val_err else resp.text[:400]
        )
        self.log.diagnose_failure(
            "POST /Account/Login (Did not redirect to oauthredirect)",
            resp.status_code,
            cleaned_err,
            self._idp_headers(),
        )
        raise RuntimeError("Login form submission did not yield an authorization code.")

    def exchange_code_for_token(self, code: str, code_verifier: str) -> TokenGrantResponse:
        """
        Exchanges the authorization code for an access token via `POST /connect/token`
        matching `getAccessToken` in `firka/lib/api/token_grant.dart`.
        """
        token_url = f"{KretaEndpoints.idp(self.mock_base_url)}/connect/token"
        form_data = {
            "code": code,
            "code_verifier": code_verifier,
            "redirect_uri": KretaConstants.REDIRECT_URI,
            "client_id": self.client_id,
            "grant_type": "authorization_code",
        }
        headers = self._idp_headers()
        self.log.info(f"Exchanging authorization code at {token_url}...")
        resp = self.session.post(token_url, data=form_data, headers=headers, timeout=20)

        if resp.status_code != 200:
            self.log.diagnose_failure("POST /connect/token (authorization_code)", resp.status_code, resp.text, headers)
            if resp.status_code == 401:
                raise InvalidGrantException("Invalid grant (HTTP 401)")
            raise RuntimeError(f"Token exchange failed with status {resp.status_code}")

        self.token_grant = TokenGrantResponse.from_json(resp.json())
        self.log.ok(
            f"Received TokenGrantResponse (token_type={self.token_grant.token_type}, "
            f"expires_in={self.token_grant.expires_in}s)"
        )
        return self.token_grant

    def authenticate_password_grant(self) -> TokenGrantResponse:
        """
        Legacy / Mock `grant_type=password` flow (from `firka/lib/api/mock_login.dart`
        and `kreta_v2.py` with `/nonce` HMAC signature if supported).
        """
        idp_base = KretaEndpoints.idp(self.mock_base_url)
        token_url = f"{idp_base}/connect/token"
        headers = self._idp_headers()

        # Attempt to fetch /nonce for X-AuthorizationPolicy-* headers (ignored if 404 on mock server)
        try:
            nonce_resp = self.session.get(
                f"{idp_base}/nonce", headers={"User-Agent": self.user_agent}, timeout=10
            )
            if nonce_resp.status_code == 200 and nonce_resp.text.strip():
                nonce = nonce_resp.text.strip()
                msg = f"{self.iss.upper()}{nonce}{self.username.upper()}".encode("utf-8")
                sig = base64.b64encode(
                    hmac.new(KretaConstants.LEGACY_HMAC_KEY, msg, hashlib.sha512).digest()
                ).decode("ascii")
                headers.update(
                    {
                        "X-AuthorizationPolicy-Key": sig,
                        "X-AuthorizationPolicy-Version": "v2",
                        "X-AuthorizationPolicy-Nonce": nonce,
                    }
                )
                self.log.info(f"Attached X-AuthorizationPolicy-Key for nonce={nonce[:10]}...")
        except requests.RequestException:
            pass

        form_data = {
            "userName": self.username,
            "username": self.username,
            "password": self.password,
            "institute_code": self.iss,
            "grant_type": "password",
            "client_id": self.client_id,
        }
        self.log.info(f"Requesting token via grant_type=password at {token_url}...")
        resp = self.session.post(token_url, data=form_data, headers=headers, timeout=20)
        if resp.status_code != 200:
            self.log.diagnose_failure("POST /connect/token (password)", resp.status_code, resp.text, headers)
            raise RuntimeError(f"Password grant failed with status {resp.status_code}")

        self.token_grant = TokenGrantResponse.from_json(resp.json())
        self.log.ok(f"Received TokenGrantResponse (expires_in={self.token_grant.expires_in}s)")
        return self.token_grant

    def refresh_access_token(self) -> TokenGrantResponse:
        """
        Refreshes the access token using `grant_type=refresh_token`, matching
        `extendToken` in `firka/lib/api/token_grant.dart`.
        """
        if not self.token_grant or not self.token_grant.refresh_token:
            raise RuntimeError("No refresh_token available to refresh")

        token_url = f"{KretaEndpoints.idp(self.mock_base_url)}/connect/token"
        headers = self._idp_headers()
        form_data = {
            "institute_code": self.iss,
            "refresh_token": self.token_grant.refresh_token,
            "grant_type": "refresh_token",
            "client_id": self.client_id,
        }
        self.log.info("Testing token refresh (grant_type=refresh_token)...")
        resp = self.session.post(token_url, data=form_data, headers=headers, timeout=20)
        if resp.status_code in (400, 401):
            self.log.diagnose_failure("POST /connect/token (refresh_token)", resp.status_code, resp.text, headers)
            if resp.status_code == 400:
                raise TokenExpiredException("Refresh token expired (HTTP 400)")
            raise InvalidGrantException("Invalid refresh grant (HTTP 401)")
        if resp.status_code != 200:
            self.log.diagnose_failure("POST /connect/token (refresh_token)", resp.status_code, resp.text, headers)
            raise RuntimeError(f"Token refresh failed with status {resp.status_code}")

        self.token_grant = TokenGrantResponse.from_json(resp.json())
        self.log.ok("Token refresh succeeded and issued a new access_token + refresh_token")
        return self.token_grant

    def validate_token(self) -> dict[str, Any]:
        """
        Validates the retrieved `access_token` / `id_token` structure and claims,
        matching `TokenModel.fromResp` in `firka_common/lib/data/models/token_model.dart`.
        """
        if not self.token_grant or not self.token_grant.access_token:
            raise RuntimeError("No access token present")

        claims: dict[str, Any] = {}
        for label, raw_tok in (("id_token", self.token_grant.id_token), ("access_token", self.token_grant.access_token)):
            if not raw_tok or "." not in raw_tok:
                continue
            try:
                decoded = decode_jwt_payload(raw_tok)
                claims.update(decoded)
                self.log.ok(f"Decoded {label} JWT payload ({len(decoded)} claims)")
            except Exception as exc:
                self.log.warn(f"Could not decode {label} as JWT ({exc}); treating as opaque token")

        if claims:
            token_iss = claims.get("kreta:institute_code") or claims.get("institute_code")
            user_name = claims.get("kreta:user_name") or claims.get("sub")
            user_id = claims.get("kreta:institute_user_id")
            exp = claims.get("exp")

            if token_iss:
                self.log.info(f"Claim kreta:institute_code    : {token_iss}")
                if self.iss != "firka-test" and token_iss.lower() != self.iss.lower():
                    self.log.warn(
                        f"Configured institution '{self.iss}' differs from JWT claim '{token_iss}'! "
                        f"Updating target iss to '{token_iss}'."
                    )
                    self.iss = token_iss
            if user_name:
                self.log.info(f"Claim kreta:user_name         : {user_name}")
            if user_id:
                self.log.info(f"Claim kreta:institute_user_id : {user_id}")
            if isinstance(exp, (int, float)):
                exp_dt = dt.datetime.fromtimestamp(exp, tz=dt.timezone.utc)
                now_dt = dt.datetime.now(tz=dt.timezone.utc)
                remaining = int((exp_dt - now_dt).total_seconds())
                if remaining <= 0:
                    raise TokenExpiredException(f"Access token already expired at {exp_dt.isoformat()}")
                self.log.ok(f"Token expiration verified     : valid for {remaining}s (until {exp_dt.isoformat()})")
        else:
            self.log.info(
                f"Opaque token validated (length={len(self.token_grant.access_token)}, "
                f"expires_in={self.token_grant.expires_in}s)"
            )

        return claims

    def _get_json(self, url: str, context: str) -> Any:
        headers = self._api_headers()
        self.log.info(f"GET {url}")
        resp = self.session.get(url, headers=headers, timeout=20)
        if resp.status_code != 200:
            self.log.diagnose_failure(context, resp.status_code, resp.text, headers)
            raise RuntimeError(f"{context} failed with HTTP {resp.status_code}")
        if not resp.text.strip():
            self.log.warn(f"{context} returned HTTP 200 with empty body (possible stale session)")
            return []
        return resp.json()

    def fetch_todays_timetable(self, target_date: dt.date | None = None) -> list[dict[str, Any]]:
        """
        Fetches timetable lessons for `target_date` (defaults to today) using
        `KretaEndpoints.getTimeTable(iss, from, to)` and parses fields defined in
        `kreta_api/lib/src/model/timetable.dart` (`Lesson.fromJson`).
        """
        day = target_date or dt.date.today()
        url = KretaEndpoints.get_timetable(self.iss, day, day, self.mock_base_url)
        data = self._get_json(url, "Fetch Today's Timetable (OrarendElemek)")
        lessons = data if isinstance(data, list) else [data]
        lessons.sort(key=lambda item: item.get("KezdetIdopont", ""))
        return lessons

    def fetch_recent_grades(self, limit: int = 5) -> list[dict[str, Any]]:
        """
        Fetches student evaluations using `KretaEndpoints.getGrades(iss)` and
        returns the `limit` most recent grades sorted by `RogzitesDatuma`
        (matching `Grade.fromJson` in `kreta_api/lib/src/model/grade.dart`).
        """
        url = KretaEndpoints.get_grades(self.iss, mock_base=self.mock_base_url)
        data = self._get_json(url, "Fetch Student Evaluations (Ertekelesek)")
        grades = data if isinstance(data, list) else [data]
        grades.sort(
            key=lambda g: g.get("RogzitesDatuma") or g.get("KeszitesDatuma") or "",
            reverse=True,
        )
        return grades[:limit]


# ============================================================================
# 6. Built-in Local Mock Server for `--self-test` (mirrors mock_kreta_server)
# ============================================================================

def _run_self_test(logger: StepLogger) -> int:
    """
    Spins up an in-process HTTP server implementing the exact wire contract
    tested in `kreta_api/test/mock_kreta_server_test.dart` plus `OrarendElemek`
    and `Ertekelesek`, then runs the full CLI workflow against it.
    """
    from http.server import BaseHTTPRequestHandler, HTTPServer
    import threading

    today_str = dt.date.today().strftime("%Y-%m-%d")
    now_iso = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    def make_jwt(payload: dict[str, Any]) -> str:
        header_b64 = base64.urlsafe_b64encode(b'{"alg":"none","typ":"JWT"}').decode().rstrip("=")
        body_b64 = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip("=")
        return f"{header_b64}.{body_b64}.sig"

    class MockKretaHandler(BaseHTTPRequestHandler):
        def log_message(self, format: str, *args: Any) -> None:
            pass  # keep console output clean

        def do_GET(self) -> None:
            parsed = urllib.parse.urlparse(self.path)
            if parsed.path == "/Account/Login":
                body = (
                    '<html><body><form class="loading-form" action="/Account/Login" method="post">'
                    '<input type="hidden" id="ReturnUrl" name="ReturnUrl" value="/connect/authorize/callback" />'
                    '<input type="hidden" id="ClientId" name="ClientId" value="" />'
                    '<input type="hidden" id="IsTemporaryLogin" name="IsTemporaryLogin" value="False" />'
                    '<input placeholder="Felhasználónév" type="text" id="UserName" name="UserName" value="71234567890" />'
                    '<input placeholder="Jelszó" type="password" id="Password" name="Password" />'
                    '<select id="InstituteCode" name="InstituteCode">'
                    '<option selected="selected" value="firka-test">Firka Test Institution</option>'
                    "</select>"
                    '<input type="hidden" id="loginType" name="loginType" value="InstituteLogin" />'
                    '<input name="__RequestVerificationToken" type="hidden" value="mock_csrf_token_123" />'
                    "</form></body></html>"
                )
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Set-Cookie", ".AspNetCore.Antiforgery.mock=csrf_cookie_val; Path=/")
                self.end_headers()
                self.wfile.write(body.encode("utf-8"))
                return

            # Protected endpoints check Bearer header and User-Agent
            auth = self.headers.get("Authorization", "")
            if not auth.startswith("Bearer "):
                self.send_response(401)
                self.end_headers()
                self.wfile.write(b'{"error":"unauthorized"}')
                return

            if parsed.path == "/ellenorzo/v3/sajat/OrarendElemek":
                lessons = [
                    {
                        "Uid": "1001,2026-11-10",
                        "Datum": f"{today_str}T00:00:00Z",
                        "KezdetIdopont": f"{today_str}T08:00:00Z",
                        "VegIdopont": f"{today_str}T08:45:00Z",
                        "Nev": "Matematika",
                        "Oraszam": 1,
                        "OraEvesSorszama": 42,
                        "TanarNeve": "Dr. Kovács János",
                        "TeremNeve": "204",
                        "Tema": "Másodfokú egyenletek",
                        "Tipus": {"Uid": "1,tanora", "Nev": "tanora", "Leiras": "Tanóra"},
                        "Allapot": {"Uid": "1,megtartott", "Nev": "megtartott", "Leiras": "Megtartott"},
                        "IsTanuloHaziFeladatEnabled": True,
                        "IsHaziFeladatMegoldva": False,
                        "Csatolmanyok": [],
                        "IsDigitalisOra": False,
                        "Letrehozas": now_iso,
                        "UtolsoModositas": now_iso,
                    },
                    {
                        "Uid": "1002,2026-11-10",
                        "Datum": f"{today_str}T00:00:00Z",
                        "KezdetIdopont": f"{today_str}T09:00:00Z",
                        "VegIdopont": f"{today_str}T09:45:00Z",
                        "Nev": "Történelem",
                        "Oraszam": 2,
                        "OraEvesSorszama": 28,
                        "TanarNeve": "Nagy Éva",
                        "TeremNeve": "108",
                        "Tema": "Az ipari forradalom",
                        "Tipus": {"Uid": "1,tanora", "Nev": "tanora", "Leiras": "Tanóra"},
                        "Allapot": {"Uid": "1,megtartott", "Nev": "megtartott", "Leiras": "Megtartott"},
                        "IsTanuloHaziFeladatEnabled": False,
                        "IsHaziFeladatMegoldva": False,
                        "Csatolmanyok": [],
                        "IsDigitalisOra": False,
                        "Letrehozas": now_iso,
                        "UtolsoModositas": now_iso,
                    },
                ]
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(lessons).encode("utf-8"))
                return

            if parsed.path == "/ellenorzo/v3/sajat/Ertekelesek":
                grades = [
                    {
                        "Uid": f"grade-{i}",
                        "RogzitesDatuma": f"2026-11-0{i}T10:15:00Z",
                        "KeszitesDatuma": f"2026-11-0{i}T10:15:00Z",
                        "Tantargy": {
                            "Uid": f"subj-{i}",
                            "Nev": subj,
                            "Kategoria": {"Uid": "1,k", "Nev": "k", "Leiras": "Közismereti"},
                            "SortIndex": i,
                        },
                        "Tema": topic,
                        "Tipus": {"Uid": "1,evkozi_jegy_ertekeles", "Nev": "evkozi_jegy_ertekeles", "Leiras": "Évközi jegy/értékelés"},
                        "Mod": {"Uid": "1,irasbeli", "Nev": "irasbeli", "Leiras": "Írásbeli"},
                        "ErtekFajta": {"Uid": "1,Osztalyzat", "Nev": "Osztalyzat", "Leiras": "Osztályzat (1-5)"},
                        "ErtekeloTanarNeve": teacher,
                        "SzamErtek": val,
                        "SzovegesErtek": str(val),
                        "SulySzazalekErteke": weight,
                        "OsztalyCsoport": {"Uid": "cg-1"},
                        "SortIndex": i,
                    }
                    for i, (subj, topic, teacher, val, weight) in enumerate(
                        [
                            ("Matematika", "Sorozatok témazáró", "Dr. Kovács János", 5, 200),
                            ("Magyar nyelv és irodalom", "Esszéírás", "Szabó Anna", 4, 100),
                            ("Történelem", "Reformkor röpdolgozat", "Nagy Éva", 5, 50),
                            ("Fizika", "Hőtan felelet", "Tóth Péter", 5, 100),
                            ("Angol nyelv", "Szódolgozat", "Kiss Eszter", 4, 50),
                            ("Biológia", "Sejttan", "Varga Judit", 5, 100),
                        ],
                        start=1,
                    )
                ]
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(grades).encode("utf-8"))
                return

            self.send_response(404)
            self.end_headers()

        def do_POST(self) -> None:
            parsed = urllib.parse.urlparse(self.path)
            length = int(self.headers.get("Content-Length", "0"))
            raw_body = self.rfile.read(length).decode("utf-8")
            form = urllib.parse.parse_qs(raw_body)

            if parsed.path == "/Account/Login":
                ctype = self.headers.get("Content-Type", "")
                cookie = self.headers.get("Cookie", "")
                expected_keys = [
                    "UserName",
                    "Password",
                    "InstituteCode",
                    "ReturnUrl",
                    "__RequestVerificationToken",
                ]
                if (
                    "application/x-www-form-urlencoded" not in ctype
                    or list(form.keys()) != expected_keys
                    or ".AspNetCore.Antiforgery.mock=csrf_cookie_val" not in cookie
                ):
                    self.send_response(400)
                    self.end_headers()
                    self.wfile.write(
                        f"Invalid login POST: ctype={ctype}, keys={list(form.keys())}, cookie={cookie}".encode(
                            "utf-8"
                        )
                    )
                    return

                self.send_response(302)
                self.send_header(
                    "Location",
                    f"{KretaConstants.REDIRECT_URI}?code=mock_auth_code_987654&state=ok",
                )
                self.end_headers()
                return

            if parsed.path == "/connect/token":
                grant_type = form.get("grant_type", [""])[0]
                if grant_type in ("authorization_code", "refresh_token", "password"):
                    exp_ts = int(dt.datetime.now(dt.timezone.utc).timestamp()) + 1800
                    jwt_tok = make_jwt(
                        {
                            "kreta:institute_code": "firka-test",
                            "kreta:institute_user_id": "71234567890",
                            "kreta:user_name": "71234567890",
                            "iat": exp_ts - 1800,
                            "exp": exp_ts,
                        }
                    )
                    resp_payload = {
                        "id_token": jwt_tok,
                        "access_token": jwt_tok,
                        "expires_in": 1800,
                        "token_type": "Bearer",
                        "refresh_token": f"mock_refresh_{secrets.token_hex(4)}",
                        "scope": KretaConstants.SCOPES,
                    }
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps(resp_payload).encode("utf-8"))
                    return

                self.send_response(400)
                self.end_headers()
                self.wfile.write(b'{"error":"invalid_grant"}')
                return

    server = HTTPServer(("127.0.0.1", 0), MockKretaHandler)
    port = server.server_address[1]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        logger.info(f"Started embedded mock Kréta server on http://127.0.0.1:{port}")
        return run_workflow(
            iss="firka-test",
            username="71234567890",
            password="mock_password",
            logger=logger,
            mock_base_url=f"http://127.0.0.1:{port}",
            flow="pkce",
            manual_auth_code=None,
            test_refresh=True,
        )
    finally:
        server.shutdown()


# ============================================================================
# 7. Main Workflow Execution
# ============================================================================

def run_workflow(
    iss: str,
    username: str,
    password: str,
    logger: StepLogger,
    mock_base_url: str | None = None,
    flow: str = "pkce",
    manual_auth_code: str | None = None,
    test_refresh: bool = False,
) -> int:
    total_steps = 4
    client = KretaTestClient(
        iss=iss,
        username=username,
        password=password,
        logger=logger,
        mock_base_url=mock_base_url,
    )

    try:
        # Step 1: Authentication
        logger.step(1, total_steps, f"IDP OAuth2 Authentication (flow={flow})")
        if flow == "password":
            client.authenticate_password_grant()
        else:
            client.authenticate_pkce(manual_auth_code=manual_auth_code)

        # Step 2: Token Validation (& optional refresh check)
        logger.step(2, total_steps, "Validate Access Token & Claims")
        client.validate_token()
        if test_refresh and client.token_grant and client.token_grant.refresh_token:
            client.refresh_access_token()

        # Step 3: Fetch Today's Timetable
        today = dt.date.today()
        logger.step(3, total_steps, f"Fetch Today's Timetable Lessons ({today.isoformat()})")
        lessons = client.fetch_todays_timetable(today)
        logger.ok(f"Retrieved {len(lessons)} lesson(s) for {today.isoformat()}")
        for idx, lesson in enumerate(lessons, start=1):
            num = lesson.get("Oraszam", "-")
            name = lesson.get("Nev") or (lesson.get("Tantargy") or {}).get("Nev", "Unknown")
            start = (lesson.get("KezdetIdopont") or "")[11:16]
            end = (lesson.get("VegIdopont") or "")[11:16]
            room = lesson.get("TeremNeve") or "-"
            teacher = lesson.get("HelyettesTanarNeve") or lesson.get("TanarNeve") or "-"
            theme = lesson.get("Tema") or ""
            print(f"    {idx}. [{num}. óra | {start}-{end}] {name} (Terem: {room}, Tanár: {teacher}) {f'- {theme}' if theme else ''}")

        # Step 4: Fetch 5 Most Recent Grades
        logger.step(4, total_steps, "Fetch 5 Most Recent Evaluations / Grades")
        grades = client.fetch_recent_grades(limit=5)
        logger.ok(f"Retrieved {len(grades)} recent evaluation(s)")
        for idx, grade in enumerate(grades, start=1):
            subj = (grade.get("Tantargy") or {}).get("Nev", "Unknown")
            val = grade.get("SzamErtek") or grade.get("SzovegesErtek", "?")
            weight = grade.get("SulySzazalekErteke")
            weight_str = f"{weight}%" if weight is not None else "-"
            rec_date = (grade.get("RogzitesDatuma") or "")[:10]
            topic = grade.get("Tema") or "-"
            teacher = grade.get("ErtekeloTanarNeve") or "-"
            print(f"    {idx}. [{rec_date}] {subj}: {val} ({weight_str}) — Téma: {topic} ({teacher})")

        print()
        logger.ok("All CLI test steps completed successfully.")
        return 0

    except Exception as exc:
        logger.fail(f"Execution aborted: {exc}")
        return 1


def resolve_credentials(args: argparse.Namespace, logger: StepLogger) -> tuple[str, str, str, str | None]:
    """Reads credentials from CLI flags, `.env`, environment variables, or interactive terminal input."""
    env_file = Path(args.env_file)
    dotenv_vars = load_dotenv_file(env_file)
    if dotenv_vars:
        logger.info(f"Loaded configuration from {env_file.resolve()}")

    def get_val(cli_val: str | None, *keys: str) -> str:
        if cli_val:
            return cli_val.strip()
        for k in keys:
            v = os.environ.get(k) or dotenv_vars.get(k)
            if v and v.strip():
                return v.strip()
        return ""

    iss = get_val(args.iss, "KRETA_INSTITUTION_ID", "KRETA_ISS", "INSTITUTION_ID")
    username = get_val(args.username, "KRETA_USERNAME", "USERNAME")
    password = get_val(args.password, "KRETA_PASSWORD", "PASSWORD")
    mock_base = get_val(args.base_url, "MOCK_KRETA_SERVER_URL") or None

    if not iss:
        iss = input("Enter Institution ID (e.g. klik035220001): ").strip()
    if not username:
        username = input("Enter Kréta Username (Student ID): ").strip()
    if not password and not args.auth_code:
        password = getpass.getpass("Enter Kréta Password: ")

    return iss, username, password, mock_base


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Standalone E-Kréta API v3 Authentication & Data Retrieval CLI Test Script"
    )
    parser.add_argument("--env-file", default=".env", help="Path to .env file (default: .env)")
    parser.add_argument("--iss", help="Institution code (overrides .env KRETA_INSTITUTION_ID)")
    parser.add_argument("--username", help="Student username (overrides .env KRETA_USERNAME)")
    parser.add_argument("--password", help="Student password (overrides .env KRETA_PASSWORD)")
    parser.add_argument(
        "--base-url",
        help="Optional mock server URL (overrides MOCK_KRETA_SERVER_URL)",
    )
    parser.add_argument(
        "--flow",
        choices=["pkce", "password"],
        default="pkce",
        help="OAuth2 flow to execute: 'pkce' (default v3) or 'password' (legacy/mock)",
    )
    parser.add_argument(
        "--auth-code",
        help="Optional pre-obtained OAuth2 authorization code (if login was completed in a browser)",
    )
    parser.add_argument(
        "--test-refresh",
        action="store_true",
        help="Also test the refresh_token grant after initial token validation",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Run end-to-end verification against an embedded mock Kréta server",
    )

    args = parser.parse_args()
    logger = StepLogger()

    if args.self_test:
        return _run_self_test(logger)

    iss, username, password, mock_base = resolve_credentials(args, logger)
    if not iss or (not username and not args.auth_code):
        logger.fail("Institution ID and Username are required.")
        return 1

    return run_workflow(
        iss=iss,
        username=username,
        password=password,
        logger=logger,
        mock_base_url=mock_base,
        flow=args.flow,
        manual_auth_code=args.auth_code,
        test_refresh=args.test_refresh,
    )


if __name__ == "__main__":
    sys.exit(main())
