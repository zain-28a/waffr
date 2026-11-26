# sql

SQL that is run by hand against the production database. The API never runs
these files; its own schema changes happen at startup in
`database.create_tables`.

| File | Purpose |
| --- | --- |
| `admin_readonly.sql` | Creates the `admin_view` schema and the `waffr_admin` login for pgAdmin: account details and money figures only, no notes, names, settings or password hashes. |

## admin_readonly.sql

Run it in pgAdmin's Query Tool while connected as the main database user
(the role the API uses). It refuses to run, and changes nothing, unless the
same session first sets a confirmation and the login's password:

```sql
SET waffr.confirm_admin = 'create-read-only-admin';
SET waffr.admin_password = '<a random password of 20+ characters>';
```

Never commit the password. Re-running it is safe: it refreshes the views and
sets the login's password to the one given, which also replaces the
`CHANGE_ME` password older versions of the script used. Afterwards run
`RESET waffr.admin_password;`.

Render databases accept outside connections from any address unless you
limit them: under the database's **Networking / Access Control**, allow only
the addresses you connect from.

The views run with their owner's rights, and `row_security.py` gives the
`waffr_admin` role a read policy on every owned table, so the views work
with row security on. Connected as the API's own role, the tables look empty
until you run `SET app.system = 'on';` in that session.

If you add a column the admin should see, add it to the view here; if you add
a table, also give it a policy in `row_security.py` (startup refuses tables
without one).
