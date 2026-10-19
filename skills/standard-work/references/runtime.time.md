# Time: Model the Meaning First

Time is not one data type. Before choosing a type or database column, ask what the value means, whose calendar applies, and whether it represents a historical fact or a future intention.

## Choose the Right Concept

| Concept | Meaning | Example |
| --- | --- | --- |
| Instant | A single point on the global timeline | When a payment was received |
| Date | A calendar day, with no time or zone | A birthday or invoice date |
| Local time | A wall-clock time, with no date or zone | A store opens at 09:00 |
| Local date-time | A calendar date and wall-clock time, not yet a unique instant | An appointment requested for 2026-11-01 at 01:30 |
| Offset date-time | A local date-time plus a UTC offset; identifies an instant, not a time zone | `2026-01-15T09:00:00-05:00` |
| Zoned date-time | A local date-time interpreted using a named time zone and its rules | 09:00 in `America/New_York` on a particular date |
| Duration | An elapsed amount of time | A timeout of 30 seconds |
| Calendar period | Calendar arithmetic, requiring calendar/context rules | One month or one calendar day |

- Do not represent a date-only value as midnight UTC. Converting it to another zone can change the date.
- A local date-time alone does not identify an instant. A UTC offset identifies an instant but does not preserve the zone's future rules.
- Distinguish elapsed duration from calendar arithmetic: “in 24 hours” and “tomorrow at the same local time” are different requirements.
- Prefer semantic types and explicit names (`expiresAt`, `birthDate`, `openingTime`, `timeZoneId`, `timeoutMs`) over a generic `date` or unqualified numeric timestamp.

## UTC Is for Instants, Not Everything

- Store and exchange historical instants in UTC. Convert to the relevant zone at presentation or business-rule boundaries.
- Preserve date-only values as dates and local times as local times. “Store everything as UTC” loses information for these concepts.
- For future local appointments and recurring schedules, preserve the intended local date/time and named zone. Decide whether the promise is a fixed instant or a local wall-clock time.
- A derived UTC instant can be useful for execution, but define whether to recompute it if time-zone rules change. Governments change these rules; keep time-zone data current.
- The relevant zone may belong to a user, venue, tenant, or contract—not the server or the person currently viewing the record.

## Time Zones and Daylight Saving

- Prefer IANA zone identifiers such as `America/New_York`. Abbreviations such as `CST` are ambiguous; a fixed offset such as `-05:00` is not a zone.
- Define mappings explicitly when a platform or integration requires another zone-ID system. Do not assume all environments accept the same identifiers.
- Local times can be **missing** when clocks move forward or **occur twice** when clocks move backward. Explicitly reject, shift, or choose an occurrence; do not silently inherit a library default for important business behavior.
- A local day is not always 24 hours, and offsets need not be whole hours. Do not hand-roll zone arithmetic.
- For “every day at 09:00,” calculate occurrences using the named zone and calendar rules; do not repeatedly add 24 hours to an instant.
- Time-zone changes by a user should not silently rewrite historical facts. Decide which zone governs existing schedules and reports.

## Calendar Arithmetic and Ranges

- Define end-of-month behavior: what does adding one month to January 31 mean? Likewise, define how leap-day anniversaries work in non-leap years.
- Use half-open intervals, `[start, end)`, for time ranges. Adjacent ranges then compose without gaps or double-counting.
- For a local-day query, resolve that date's start and the next date's start in the relevant zone, then query the resulting instant range. Do not add a fixed 24 hours or manufacture `23:59:59.999`.
- “Today,” week boundaries, business days, and holidays require explicit zone/calendar policies. Not every week starts on Monday and not every working week is Monday–Friday.

## Parsing, Serialization, and Storage

- Use an explicit wire contract: ISO-8601 dates (`YYYY-MM-DD`), instants with `Z` or an explicit offset, and separate named-zone fields when zone intent matters.
- Reject ambiguous locale-dependent input such as `01/02/2026` at machine boundaries. Use locale-aware formatting for people, not as a persistence format.
- Specify timestamp units and precision. Epoch seconds and milliseconds are not interchangeable; round-trips through databases or JSON may truncate fractional seconds.
- Compare parsed instants, not arbitrary timestamp strings. Different offsets and precision can break lexical ordering.
- Database type names are not portable semantics. Verify the chosen database and driver: PostgreSQL `timestamptz` represents an instant but does not retain the original zone ID; `timestamp without time zone` does not identify an instant on its own.

## Runtime Clocks Are Not Perfect

- Wall clocks can jump due to synchronization or manual changes. Use a monotonic clock for elapsed time, performance measurements, and in-process timeout budgets.
- Monotonic readings are not portable timestamps: do not persist them or compare them across processes or machines.
- Distributed wall clocks can disagree. Do not treat timestamp ordering as proof of causality or uniqueness; use explicit versions, sequences, or concurrency controls when ordering matters.
- Make “now” a dependency and capture it once when an operation needs a consistent instant. See [time and deterministic tests](runtime.testing.md#time-and-deterministic-tests) for fake clocks, timers, and .NET `TimeProvider`.

## Language Gotchas

### JavaScript / TypeScript

- `Date` represents an instant with millisecond precision, not a date-only or zoned value. It does not retain the input's original zone.
- `Date` local getters and constructors use the host's zone; UTC methods have different semantics. Do not let server defaults determine business dates.
- Parsing `YYYY-MM-DD` as a `Date` uses UTC, while a date-time without an offset is interpreted locally. Avoid these implicit conversions; preserve date-only values separately and require offsets for instants.
- Use Temporal where supported, or a maintained library with explicit date/time/zone types. Check runtime support rather than assuming it.

### .NET

- Prefer `DateOnly` and `TimeOnly` for date-only and time-only concepts.
- Use `DateTimeOffset` for instants and offset-bearing values. It retains an offset, not a named time zone; store the zone separately when needed.
- `DateTime.Kind` (`Utc`, `Local`, `Unspecified`) matters. An `Unspecified` value is not automatically UTC, and `DateTime.SpecifyKind` relabels a value rather than converting it.
- Use `TimeZoneInfo` for zone conversion and explicitly handle invalid or ambiguous local times. Consider Noda Time when richer distinctions such as `Instant`, `LocalDate`, `LocalDateTime`, `ZonedDateTime`, `Duration`, and `Period` materially simplify the domain.
- `TimeSpan` represents a fixed duration, not a calendar month. Use `TimeProvider` for runtime clock and timer dependencies, as described in the testing reference.

## Review Checklist

- What concept does each value represent, and does its type preserve that meaning?
- Whose zone and calendar govern the rule? Are they explicit?
- What happens at DST gaps/overlaps, leap days, month ends, and exact boundaries?
- Is the requirement elapsed time or calendar time? Fixed instant or future local intention?
- Do serialization and storage preserve the required precision and zone intent?
- Can tests control both “now” and scheduled work without sleeping?
