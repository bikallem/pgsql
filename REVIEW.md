# Code Review — bikallem/postgresql

Comprehensive review of the PostgreSQL MoonBit driver codebase.
Each item has a checkbox for tracking progress.

## Critical: Security

- [ ] **1. SQL injection in savepoint methods** (`src/transaction.mbt:138,150,159`)
  `savepoint`, `rollback_to`, and `release` concatenate the `name` parameter directly into SQL without identifier quoting. A malicious name like `"foo; DROP TABLE users"` would execute arbitrary SQL. Fix: quote identifiers with double quotes and escape internal double quotes.

## High: Correctness

- [ ] **2. No `Terminate` message on close** (`src/connection.mbt:129`)
  `Connection::close` just closes the socket without sending `Terminate` (`'X'`). PostgreSQL protocol requires this for clean shutdown; the server logs unclean disconnections.

- [ ] **3. Silent lossy coercion in `Value::as_int`** (`src/value.mbt:48`)
  `Int64(9999999999L).as_int()` silently truncates to 32 bits. `Float(3.9).as_int()` silently truncates to 3. No error or `None`. Similar issues in `as_int64` (Float truncation) and `as_float` (Int64 precision loss for values > 2^53).

- [ ] **4. `Config` derives `Show`, exposing passwords** (`src/config.mbt:18`)
  If a `Config` is printed in logs or error messages, the password is visible in plaintext. Implement `Show` manually to mask the password field.

- [ ] **5. Float special values not parsed** (`src/protocol/types.mbt:259`)
  PostgreSQL can return `NaN`, `Infinity`, `-Infinity` for float columns. `parse_float` would return `String("NaN")` instead of a Float value, breaking typed access.

- [ ] **6. `parse_bool` too permissive** (`src/protocol/types.mbt:199`)
  Anything not `"t"/"true"/"TRUE"/"1"` becomes `false`. Input like `"garbage"` parses as `Bool(false)` instead of falling back to `String`. Should explicitly check false values and fall back to `String` for unrecognized input.

- [ ] **7. Integer overflow in `parse_int`/`parse_int64`** (`src/protocol/types.mbt:209,234`)
  No overflow check. Values exceeding Int/Int64 range silently wrap. Should detect overflow and fall back to `String` or `Float`.

## Medium: Design & Robustness

- [x] **8. No socket read timeout** (`connection.mbt`)
  Added `read_timeout` config option (milliseconds). Uses `@async.with_timeout` to wrap `read_some()`, raising `ConnectionClosedError` on timeout. Default 0 (no timeout).

- [ ] **9. Unknown auth mechanisms silently ignored** (`src/connection.mbt:206`)
  The `_ => ()` wildcard during authentication means SCRAM-SHA-256 or other unsupported mechanisms are silently skipped, causing the client to hang. Should raise `AuthError` for unrecognized auth request types.

- [ ] **10. Repeated column allocation per DataRow** (`src/client.mbt:192`)
  `proto_fields.map(column_info_from_field)` is called once per row + once for the result. For N rows, N+1 identical arrays are allocated. Should compute columns once before the loop and reuse.

- [ ] **11. `Row::is_null` returns `true` for out-of-bounds** (`src/query.mbt:169`)
  Conflates "column doesn't exist" with "column is NULL". Can mask index bugs in caller code.

- [ ] **12. `Row::get_by_name` is O(n) linear search** (`src/query.mbt:110`)
  For queries with many columns accessed by name, this is inefficient. A pre-built `Map[String, Int]` would be O(1).

- [ ] **13. PreparedStatement not invalidated on `Client::close`**
  After closing the client, outstanding `PreparedStatement` objects still have `closed = false` and will try to use a dead socket.

- [ ] **14. Decoder doesn't validate message lengths** (`src/protocol/decoder.mbt:45`)
  A malformed message with an absurd length could cause memory exhaustion. No sanity check (e.g., `len < 4 || len > MAX_SIZE`).

- [ ] **15. BufferReader has no bounds checking** (`src/protocol/buffer_reader.mbt`)
  Every read method indexes directly without checking `remaining()`. Malformed server data causes index-out-of-bounds panic instead of a recoverable error.

- [ ] **16. No message batching** (`src/client.mbt:51-64`)
  Five separate `send()` calls for one extended query. Concatenating into a single write would reduce syscalls.

## Medium: Code Smells

- [ ] **17. UTF-8 encoding duplicated 3 times**
  `src/protocol/auth.mbt:41`, `src/protocol/buffer_writer.mbt:67+96`, `src/protocol/types.mbt:362`. Same 20-line function copy-pasted. Extract a shared utility.

- [ ] **18. `hex_char_at` duplicated + O(n)**
  `src/protocol/auth.mbt:81`, `src/protocol/types.mbt:455`. Linear scan through hex string. Replace with a `FixedArray[Byte]` lookup table and deduplicate.

- [ ] **19. MD5 `s` and `k` tables reallocated per call** (`src/protocol/auth.mbt:107-125`)
  Static constants allocated inside the function body on every invocation. Hoist to module-level `let` bindings.

- [ ] **20. Duplicate protocol constant definitions**
  `encoder_protocol_version` (`src/protocol/encoder.mbt:7`) duplicates `PROTOCOL_VERSION` (`src/protocol/messages.mbt:13`). Frontend message codes defined in both `encoder.mbt` and `messages.mbt`. Consolidate to one location.

- [ ] **21. Repetitive active-check guard in Transaction** (`src/transaction.mbt`)
  Every `Transaction` method starts with the same `if not(self.active) { raise TxError(...) }` block, repeated 9 times. Extract to a private `check_active` helper.

- [ ] **22. `parse_text_value_inner` uses magic OID numbers** (`src/protocol/types.mbt:172`)
  Uses `16U` instead of the defined `OID_BOOL` constant. Same for other OIDs. Use named constants.

- [ ] **23. Duplicated Bind/Describe/Execute/Sync sequence**
  Nearly identical protocol message sequence in `src/client.mbt:query_params` and `src/prepared.mbt:query`. Factor into a shared helper, parameterized by statement name.

- [ ] **24. Inconsistent error naming**
  `ServerErr` vs `AuthError` vs `TxError` vs `PreparedStmtError`. No consistent suffix convention. Consider standardizing on `*Error` suffix.

## Low: Testing Gaps

- [ ] **25. Savepoint methods have zero test coverage**
  `Transaction::savepoint`, `rollback_to`, `release` are never tested (unit or integration).

- [ ] **26. No tests for Show implementations** on `ConnectionClosedError`, `AuthError`, `ServerErr`, `TxError`, `PreparedStmtError`.

- [ ] **27. No unit tests for key helpers**
  `build_query_result`, `convert_row_values`, `serialize_params`, `parse_int_simple` have no direct unit tests.

- [ ] **28. MD5 tests don't verify actual hash values** (`src/protocol/auth_wbtest.mbt`)
  Only check structural properties (starts with "md5", length 35). Should verify against known-good PostgreSQL hash output.

- [ ] **29. No malformed input tests for decoder**
  No tests for truncated messages, invalid message type codes, zero-length messages, or corrupted field data.

- [x] **30. Untested decoder paths**
  Added tests for all: `CopyOutResponse`, `NegotiateProtocolVersion`, `AuthenticationSASLContinue`, `AuthenticationSASLFinal`. Also added parser for `NegotiateProtocolVersion`.

- [ ] **31. Missing edge case tests for Value coercions**
  No tests for `Int64(large).as_int()` truncation, `Float(3.9).as_int()` truncation, `Bytes(b).as_string()` returning `None`.

- [ ] **32. No test for behavior after `Client::close`**
  What happens when calling `query()` on a closed client is undefined and untested.

- [ ] **33. No test for `TxError` path in Transaction methods**
  The `if not(self.active)` guard is never exercised in tests.

## Low: Documentation

- [x] **34. MEMORY.md paths are stale**
  Updated all paths: root-level source files, `internal/protocol/`, `tests/`, `examples/contacts/`.

- [x] **35. Integration test file header is outdated** (`tests/integration_test.mbt`)
  Fixed paths: `./tests/setup-pg.sh start` and `moon test --target native tests/`.

- [ ] **36. README doesn't mention `Bytes`, `Int64`, `Null` value types**
  Users working with `BYTEA`, `BIGINT`, or nullable columns have no documentation guidance.

- [ ] **37. Example app passes integer IDs as `String`** (`examples/contacts/main.mbt:152,166`)
  The `id` column is `SERIAL PRIMARY KEY` (integer) but is passed as `@pgsql.String(id)`. Should parse to `Int` and use `@pgsql.Int`.

- [ ] **38. Dead code after `while true`** (`src/connection.mbt:84-86`)
  Lines after the `while true` loop are unreachable. The comment "Should never reach here" confirms this. Remove.

- [ ] **39. Public methods on non-public struct** (`src/connection.mbt:103-125`)
  `Connection` is package-private but `get_process_id`, `get_secret_key`, `get_transaction_status` are `pub`. The `pub` is misleading since the struct is not exported. Remove `pub` or add a comment.

- [ ] **40. `cstring` reader claims UTF-8 but only handles ASCII** (`src/protocol/buffer_reader.mbt:106`)
  Doc says "ASCII/UTF-8" but implementation treats each byte as a char. Multi-byte UTF-8 will produce garbled output. Either implement proper UTF-8 decoding or document ASCII-only.
