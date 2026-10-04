-- One row per member: the public half of their key, never the private one.
CREATE TABLE members (
  id INTEGER PRIMARY KEY,
  username TEXT NOT NULL,
  public_key TEXT NOT NULL,
  visible INTEGER NOT NULL DEFAULT 1,
  joined_at TEXT NOT NULL,
  -- The member's own date at their last upload: their periods end on it.
  today TEXT
);
CREATE UNIQUE INDEX members_username ON members (lower(username));

-- One row per member, provider and day. Uploading a day again replaces it.
CREATE TABLE daily_tokens (
  member_id INTEGER NOT NULL REFERENCES members (id) ON DELETE CASCADE,
  provider TEXT NOT NULL,
  day TEXT NOT NULL,
  input INTEGER NOT NULL,
  output INTEGER NOT NULL,
  cache_write INTEGER NOT NULL,
  cache_read INTEGER NOT NULL,
  unsplit INTEGER NOT NULL,
  PRIMARY KEY (member_id, provider, day)
);
CREATE INDEX daily_tokens_day ON daily_tokens (day);

-- A signed request is accepted once; rows older than ten minutes are swept.
CREATE TABLE nonces (
  nonce TEXT PRIMARY KEY,
  seen_at INTEGER NOT NULL
);
