# Large reference (search read-cap regression fixture)


This document exists to be larger than the historical default per-file
read budget (`max_read_bytes` defaulted to 8192). It guards the property
that `x07.search_v1` can find content inside docs bigger than that budget,
without the caller having to raise `max_read_bytes` by hand.

The sentinel token the regression test searches for lives at the very end
of this file, past byte offset 8192, so a partial "read only the first N
bytes" implementation would also fail the test: only reading the whole file
makes the sentinel visible.

## Section 01

Paragraph 01a. Views are fat pointers; convert to owning bytes only to persist.
Paragraph 01b. Views are fat pointers; convert to owning bytes only to persist.
Paragraph 01c. Views are fat pointers; convert to owning bytes only to persist.
Paragraph 01d. Views are fat pointers; convert to owning bytes only to persist.
Paragraph 01e. Views are fat pointers; convert to owning bytes only to persist.
Paragraph 01f. Views are fat pointers; convert to owning bytes only to persist.

## Section 02

Paragraph 02a. Branded bytes carry a compile-time encoding tag under std.brand.
Paragraph 02b. Branded bytes carry a compile-time encoding tag under std.brand.
Paragraph 02c. Branded bytes carry a compile-time encoding tag under std.brand.
Paragraph 02d. Branded bytes carry a compile-time encoding tag under std.brand.
Paragraph 02e. Branded bytes carry a compile-time encoding tag under std.brand.
Paragraph 02f. Branded bytes carry a compile-time encoding tag under std.brand.

## Section 03

Paragraph 03a. Fixture worlds enforce deterministic fuel and memory budgets.
Paragraph 03b. Fixture worlds enforce deterministic fuel and memory budgets.
Paragraph 03c. Fixture worlds enforce deterministic fuel and memory budgets.
Paragraph 03d. Fixture worlds enforce deterministic fuel and memory budgets.
Paragraph 03e. Fixture worlds enforce deterministic fuel and memory budgets.
Paragraph 03f. Fixture worlds enforce deterministic fuel and memory budgets.

## Section 04

Paragraph 04a. Results carry stable numeric error codes per module namespace.
Paragraph 04b. Results carry stable numeric error codes per module namespace.
Paragraph 04c. Results carry stable numeric error codes per module namespace.
Paragraph 04d. Results carry stable numeric error codes per module namespace.
Paragraph 04e. Results carry stable numeric error codes per module namespace.
Paragraph 04f. Results carry stable numeric error codes per module namespace.

## Section 05

Paragraph 05a. Bounded, file-backed results beat unbounded context dumps.
Paragraph 05b. Bounded, file-backed results beat unbounded context dumps.
Paragraph 05c. Bounded, file-backed results beat unbounded context dumps.
Paragraph 05d. Bounded, file-backed results beat unbounded context dumps.
Paragraph 05e. Bounded, file-backed results beat unbounded context dumps.
Paragraph 05f. Bounded, file-backed results beat unbounded context dumps.

## Section 06

Paragraph 06a. Read budgets should truncate a file, never silently drop it.
Paragraph 06b. Read budgets should truncate a file, never silently drop it.
Paragraph 06c. Read budgets should truncate a file, never silently drop it.
Paragraph 06d. Read budgets should truncate a file, never silently drop it.
Paragraph 06e. Read budgets should truncate a file, never silently drop it.
Paragraph 06f. Read budgets should truncate a file, never silently drop it.

## Section 07

Paragraph 07a. Views are fat pointers; convert to owning bytes only to persist.
Paragraph 07b. Views are fat pointers; convert to owning bytes only to persist.
Paragraph 07c. Views are fat pointers; convert to owning bytes only to persist.
Paragraph 07d. Views are fat pointers; convert to owning bytes only to persist.
Paragraph 07e. Views are fat pointers; convert to owning bytes only to persist.
Paragraph 07f. Views are fat pointers; convert to owning bytes only to persist.

## Section 08

Paragraph 08a. Branded bytes carry a compile-time encoding tag under std.brand.
Paragraph 08b. Branded bytes carry a compile-time encoding tag under std.brand.
Paragraph 08c. Branded bytes carry a compile-time encoding tag under std.brand.
Paragraph 08d. Branded bytes carry a compile-time encoding tag under std.brand.
Paragraph 08e. Branded bytes carry a compile-time encoding tag under std.brand.
Paragraph 08f. Branded bytes carry a compile-time encoding tag under std.brand.

## Section 09

Paragraph 09a. Fixture worlds enforce deterministic fuel and memory budgets.
Paragraph 09b. Fixture worlds enforce deterministic fuel and memory budgets.
Paragraph 09c. Fixture worlds enforce deterministic fuel and memory budgets.
Paragraph 09d. Fixture worlds enforce deterministic fuel and memory budgets.
Paragraph 09e. Fixture worlds enforce deterministic fuel and memory budgets.
Paragraph 09f. Fixture worlds enforce deterministic fuel and memory budgets.

## Section 10

Paragraph 10a. Results carry stable numeric error codes per module namespace.
Paragraph 10b. Results carry stable numeric error codes per module namespace.
Paragraph 10c. Results carry stable numeric error codes per module namespace.
Paragraph 10d. Results carry stable numeric error codes per module namespace.
Paragraph 10e. Results carry stable numeric error codes per module namespace.
Paragraph 10f. Results carry stable numeric error codes per module namespace.

## Section 11

Paragraph 11a. Bounded, file-backed results beat unbounded context dumps.
Paragraph 11b. Bounded, file-backed results beat unbounded context dumps.
Paragraph 11c. Bounded, file-backed results beat unbounded context dumps.
Paragraph 11d. Bounded, file-backed results beat unbounded context dumps.
Paragraph 11e. Bounded, file-backed results beat unbounded context dumps.
Paragraph 11f. Bounded, file-backed results beat unbounded context dumps.

## Section 12

Paragraph 12a. Read budgets should truncate a file, never silently drop it.
Paragraph 12b. Read budgets should truncate a file, never silently drop it.
Paragraph 12c. Read budgets should truncate a file, never silently drop it.
Paragraph 12d. Read budgets should truncate a file, never silently drop it.
Paragraph 12e. Read budgets should truncate a file, never silently drop it.
Paragraph 12f. Read budgets should truncate a file, never silently drop it.

## Section 13

Paragraph 13a. Views are fat pointers; convert to owning bytes only to persist.
Paragraph 13b. Views are fat pointers; convert to owning bytes only to persist.
Paragraph 13c. Views are fat pointers; convert to owning bytes only to persist.
Paragraph 13d. Views are fat pointers; convert to owning bytes only to persist.
Paragraph 13e. Views are fat pointers; convert to owning bytes only to persist.
Paragraph 13f. Views are fat pointers; convert to owning bytes only to persist.

## Section 14

Paragraph 14a. Branded bytes carry a compile-time encoding tag under std.brand.
Paragraph 14b. Branded bytes carry a compile-time encoding tag under std.brand.
Paragraph 14c. Branded bytes carry a compile-time encoding tag under std.brand.
Paragraph 14d. Branded bytes carry a compile-time encoding tag under std.brand.
Paragraph 14e. Branded bytes carry a compile-time encoding tag under std.brand.
Paragraph 14f. Branded bytes carry a compile-time encoding tag under std.brand.

## Section 15

Paragraph 15a. Fixture worlds enforce deterministic fuel and memory budgets.
Paragraph 15b. Fixture worlds enforce deterministic fuel and memory budgets.
Paragraph 15c. Fixture worlds enforce deterministic fuel and memory budgets.
Paragraph 15d. Fixture worlds enforce deterministic fuel and memory budgets.
Paragraph 15e. Fixture worlds enforce deterministic fuel and memory budgets.
Paragraph 15f. Fixture worlds enforce deterministic fuel and memory budgets.

## Section 16

Paragraph 16a. Results carry stable numeric error codes per module namespace.
Paragraph 16b. Results carry stable numeric error codes per module namespace.
Paragraph 16c. Results carry stable numeric error codes per module namespace.
Paragraph 16d. Results carry stable numeric error codes per module namespace.
Paragraph 16e. Results carry stable numeric error codes per module namespace.
Paragraph 16f. Results carry stable numeric error codes per module namespace.

## Section 17

Paragraph 17a. Bounded, file-backed results beat unbounded context dumps.
Paragraph 17b. Bounded, file-backed results beat unbounded context dumps.
Paragraph 17c. Bounded, file-backed results beat unbounded context dumps.
Paragraph 17d. Bounded, file-backed results beat unbounded context dumps.
Paragraph 17e. Bounded, file-backed results beat unbounded context dumps.
Paragraph 17f. Bounded, file-backed results beat unbounded context dumps.

## Section 18

Paragraph 18a. Read budgets should truncate a file, never silently drop it.
Paragraph 18b. Read budgets should truncate a file, never silently drop it.
Paragraph 18c. Read budgets should truncate a file, never silently drop it.
Paragraph 18d. Read budgets should truncate a file, never silently drop it.
Paragraph 18e. Read budgets should truncate a file, never silently drop it.
Paragraph 18f. Read budgets should truncate a file, never silently drop it.

## Section 19

Paragraph 19a. Views are fat pointers; convert to owning bytes only to persist.
Paragraph 19b. Views are fat pointers; convert to owning bytes only to persist.
Paragraph 19c. Views are fat pointers; convert to owning bytes only to persist.
Paragraph 19d. Views are fat pointers; convert to owning bytes only to persist.
Paragraph 19e. Views are fat pointers; convert to owning bytes only to persist.
Paragraph 19f. Views are fat pointers; convert to owning bytes only to persist.

## Section 20

Paragraph 20a. Branded bytes carry a compile-time encoding tag under std.brand.
Paragraph 20b. Branded bytes carry a compile-time encoding tag under std.brand.
Paragraph 20c. Branded bytes carry a compile-time encoding tag under std.brand.
Paragraph 20d. Branded bytes carry a compile-time encoding tag under std.brand.
Paragraph 20e. Branded bytes carry a compile-time encoding tag under std.brand.
Paragraph 20f. Branded bytes carry a compile-time encoding tag under std.brand.

## Section 21

Paragraph 21a. Fixture worlds enforce deterministic fuel and memory budgets.
Paragraph 21b. Fixture worlds enforce deterministic fuel and memory budgets.
Paragraph 21c. Fixture worlds enforce deterministic fuel and memory budgets.
Paragraph 21d. Fixture worlds enforce deterministic fuel and memory budgets.
Paragraph 21e. Fixture worlds enforce deterministic fuel and memory budgets.
Paragraph 21f. Fixture worlds enforce deterministic fuel and memory budgets.

## Section 22

Paragraph 22a. Results carry stable numeric error codes per module namespace.
Paragraph 22b. Results carry stable numeric error codes per module namespace.
Paragraph 22c. Results carry stable numeric error codes per module namespace.
Paragraph 22d. Results carry stable numeric error codes per module namespace.
Paragraph 22e. Results carry stable numeric error codes per module namespace.
Paragraph 22f. Results carry stable numeric error codes per module namespace.

## Section 23

Paragraph 23a. Bounded, file-backed results beat unbounded context dumps.
Paragraph 23b. Bounded, file-backed results beat unbounded context dumps.
Paragraph 23c. Bounded, file-backed results beat unbounded context dumps.
Paragraph 23d. Bounded, file-backed results beat unbounded context dumps.
Paragraph 23e. Bounded, file-backed results beat unbounded context dumps.
Paragraph 23f. Bounded, file-backed results beat unbounded context dumps.

## Section 24

Paragraph 24a. Read budgets should truncate a file, never silently drop it.
Paragraph 24b. Read budgets should truncate a file, never silently drop it.
Paragraph 24c. Read budgets should truncate a file, never silently drop it.
Paragraph 24d. Read budgets should truncate a file, never silently drop it.
Paragraph 24e. Read budgets should truncate a file, never silently drop it.
Paragraph 24f. Read budgets should truncate a file, never silently drop it.

## Sentinel

The unique token below is what the regression test queries for. It must be
reachable by a default-parameter search even though it sits well past the
old eight kilobyte read budget:

zubzubsentinel deep-doc reachable by default search
