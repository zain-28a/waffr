# Waffr security

What protects the API and the app, what each common risk looks like here,
and what is still worth doing. The backend is FastAPI on Render with Render
Postgres; the app is Flutter.

## Row level security

Every table has Postgres row level security turned on and **forced**, so the
policies apply even to the table owner, which is the role the API connects as.
`backend/row_security.py` creates the policies on every startup.

| Table | Who can read | Who can write |
| --- | --- | --- |
| `users` | the account itself (`id`) | the account itself |
| `user_settings`, `transactions`, `recurring_expenses`, `savings_goals`, `savings_transfers`, `shopping_lists`, `shopping_items`, `notifications`, `expense_categories`, `expense_presets` | the owner (`user_id`) | the owner |
| `news_articles`, `exchange_rates` | everyone | the server only |

How it works:

- `get_current_user` puts the token's user id into the transaction setting
  `app.user_id`. Every policy compares the row's owner with it. A route that
  forgets its `user_id` filter still sees one account only, and writing a row
  for someone else fails in the database.
- With no setting the tables look empty. A missed binding fails closed.
- `shopping_items.list_id` and `savings_transfers.goal_id` must point at the
  same user's rows. Foreign keys skip row security, so the policies check this.
- `app.system = 'on'` is the server's own access: startup migrations, the news
  refresh, and the email lookup at sign-in (before anyone is known). It is used
  in `system_scope` for one query at a time.
- Both settings are transaction-local, so nothing carries over to the next
  request through the connection pool.
- Startup stops if a model's table has no policy, so a new table cannot ship
  without one. Add it to `OWNED_TABLES` or `PUBLIC_READ_TABLES`.
- `waffer_admin` (from `backend/sql/admin_readonly.sql`) keeps its read-only
  views.

In pgAdmin, connected as `waffer_user`, the tables now look empty. Run
`SET app.system = 'on';` in the Query Tool first.

Row security is a second lock behind the `user_id` filters in the routes. It
does not stop SQL injection: code that can run any SQL could set
`app.user_id` itself. All queries go through SQLAlchemy with bound parameters.

## Rate limits

`backend/rate_limit.py`. Over the limit, the API answers `429` with a
`Retry-After` header; the app shows "محاولات كثيرة. انتظر قليلاً ثم حاول مرة أخرى".

| What | Limit | Counted per |
| --- | --- | --- |
| Every request | 180 a minute | account (valid token) |
| Every request | 120 a minute | IP address (no valid token) |
| Sign in | 30 per 5 minutes | IP address |
| Wrong passwords | 5 per 15 minutes | email, existing or not |
| Sign up | 10 an hour; 300 an hour in total | IP address; everyone |
| Forgot password | 5 per 15 minutes; 3 an hour; 100 an hour in total | IP address; email; everyone |
| Reset with code | 10 per 15 minutes; 10 an hour | IP address; email |
| Change password | 5 per 15 minutes | account |
| Set data key | 10 an hour | account |
| Delete account | 3 an hour | account |
| Sync | 30 a minute | account |
| Manual news refresh | 2 per 10 minutes; 6 an hour in total | account; everyone |

`GET /` (Render's health check) is not limited.

The counts live in the API's memory. Render runs one instance, so that is
enough. With more instances or workers, move them to Redis first.

On Render the client address comes from the first `X-Forwarded-For` entry
(set `TRUST_PROXY_HEADERS=0` to use the socket address instead). Render says
it puts the real client first, but if a client could forge that entry it
could dodge the per-address limits. The per-email, per-account and total
limits still hold, so brute force stays bounded either way.

## The 20-point checklist

| # | Item | Status in Waffr |
| --- | --- | --- |
| 1 | Add HSTS | Done. `Strict-Transport-Security: max-age=63072000; includeSubDomains` on every response, plus `nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, a deny-all CSP and `Cache-Control: no-store`. Render redirects HTTP to HTTPS. Release Android builds no longer allow plain HTTP; iOS already blocks it. |
| 2 | Add CSRF tokens | Not needed. CSRF works by riding on cookies a browser adds by itself. The API sets no cookies; the token travels in the `Authorization` header, which a browser never adds on its own. CORS stays closed. If a cookie session is ever added, add CSRF tokens then. |
| 3 | Reset sessions on password change | Done. Changing or resetting the password bumps `token_version`, which signs out every other device; change hands back a new token for the current one. |
| 4 | Expire reset links | Done. Reset codes are 6 digits, stored hashed, expire after 15 minutes, allow 5 guesses, and work once. |
| 5 | Prevent user enumeration | Done for sign-in and password reset: same message, same timing (a dummy hash check when the email has no account), same 429 behaviour, and the reset email is looked up and sent after the reply. Sign-up still says "already registered"; see below. |
| 6 | Whitelist upload types | Nothing is uploaded. Profile photos were removed and `PUT /auth/photo` ignores its body. Every body is size-capped. |
| 7 | Verify payment webhooks | No payments. If added, check the provider's signature on the raw body before anything else. |
| 8 | Set prices server-side | No payments. Shopping prices are the user's own notes. |
| 9 | Block prompt injection | No AI model is called. Smart analysis runs on the device with fixed rules. |
| 10 | Cap AI usage | Same: no AI calls. If one is added, give it a per-account daily cap like the limits above. |
| 11 | Limit request size | Done. 256 KB per request, 25 MB for `/sync` (a first sync sends the whole ledger). Every text field has a length cap, money fits `NUMERIC(18, 2)`, and sync takes at most 50,000 rows per collection. |
| 12 | Rate limit password resets | Done. See the table above. |
| 13 | Sanitize before storing | Done. Control characters (NUL and friends) are stripped from every text field, lengths and ranges are checked, and private text is encrypted on the device before it is uploaded. The API returns JSON only, never HTML. |
| 14 | Lock down CORS | Done. No CORS headers by default, so browsers on other sites cannot read responses. `CORS_ORIGINS` (comma-separated) opens it for a named web build only, without credentials. |
| 15 | Disable directory listing | Nothing is served from disk. The old avatar folder is deleted at startup. |
| 16 | Remove default admin routes | Done. FastAPI's `/docs`, `/redoc` and `/openapi.json` are off (`ENABLE_API_DOCS=1` turns them back on). `POST /online/news/refresh` now needs an account and is tightly limited. Uvicorn no longer sends a `server` header. |
| 17 | Lock accounts after failed logins | Done. 5 wrong passwords lock sign-in for 15 minutes. The lock is stored on the account, so a restart does not lift it. Signed-in devices keep working, and a password reset lifts it. |
| 18 | Log security events | Done. JSON lines on the `waffr.security` logger (Render's Logs tab): sign-up, sign-in, failures, locks, rate limits, rejected tokens, reset requests and results, password changes, data key set, account deletion. Emails are logged as a keyed hash; passwords, codes and tokens never. |
| 19 | Set secure cookie flags | No cookies. If one is added: `Secure; HttpOnly; SameSite=Strict`. |
| 20 | Restrict database permissions | Done: forced row security on every table, and the pgAdmin login (`waffer_admin`) reads only redacted views. Startup warns if the API's role is a superuser or `BYPASSRLS`, which would skip the policies. |

## Other problems found and fixed

- **Forgeable tokens without `SECRET_KEY`.** The fallback was the public string
  `CHANGE_THIS_LATER`. Now a missing key means a random one per process
  (sign-ins end on restart), and short keys log a warning. Tokens must carry
  `exp` and `sub`, and only HS256 is accepted.
- **Database errors sent to the app.** Sync returned the raw exception text,
  which named tables and SQL. It now logs it and answers "Sync failed".
- **Unlimited, anonymous news refresh.** Anyone could make the server fetch
  both feeds and hold a worker for minutes. Now it needs an account and is
  limited.
- **Feed redirects.** A feed could redirect the server to any address before
  the host check ran. Redirects now go only to the feed's own HTTPS hosts.
- **No password rules on sign-up.** Now 8 to 256 characters, matching the app.
  Longer inputs are refused before the slow hash runs.
- **Out-of-range values.** Huge amounts or long ids reached the database and
  failed there. They are refused with a 422 first.
- **Plain HTTP on Android.** Release builds allowed it; only debug builds do now.

## Still worth doing

- **Email verification at sign-up.** It would let sign-up stop revealing which
  emails exist and stop accounts being made with someone else's address.
- **Ask for the password before deleting the account.** Today a stolen token
  is enough. Needs a change in the app as well.
- **A separate migration role.** Run `create_tables()` with an owner role and
  serve requests with a role that has only SELECT, INSERT, UPDATE and DELETE.
- **Dependency checks.** Turn on Dependabot or run `pip-audit` and
  `flutter pub outdated` regularly.
- **Alerts.** Forward the `waffr.security` lines to an alerting tool and watch
  for bursts of `login_failed`, `account_locked` and `rate_limited`.
- **Device storage.** The ledger lives unencrypted in SharedPreferences. The
  app lock covers the screen, not the files.
- **Second factor** for accounts, once there is a reason for it.

## Settings

| Variable | Default | Purpose |
| --- | --- | --- |
| `SECRET_KEY` | random per process | Signs tokens. Render generates it. Use 32+ characters. |
| `ENABLE_API_DOCS` | off | `1` serves `/docs`, `/redoc`, `/openapi.json`. |
| `CORS_ORIGINS` | empty | Comma-separated origins for a web build. |
| `TRUST_PROXY_HEADERS` | on when `RENDER=true` | Read the client address from `X-Forwarded-For`. |

## Tests

```
pip install -r backend/requirements-dev.txt
TEST_DATABASE_URL=postgresql://user:pass@localhost:5432/waffer_test python -m pytest backend/tests
```

Use a throwaway database: the tests empty every table. The role must own the
database and must not be a superuser, so row security applies as it does on
Render.
