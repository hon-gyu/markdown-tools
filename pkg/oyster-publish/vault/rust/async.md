---
title: Async Rust
tags: [rust, async]
---

# Async Rust

Lives at `vault/rust/async.md`, served at `/rust/async`. The directory tree is
the taxonomy.

Internal links work in both syntaxes: the wikilink [[rust/index]] and the plain
markdown link [back to the Rust hub](rust/index) resolve to the same page, while
an [external link](https://doc.rust-lang.org) is left untouched.

## Futures

A `Future` is a value that represents an asynchronous computation. It does
nothing until polled by an executor.

### Polling

Polling drives a future toward completion. Each poll either yields a value or
signals that the future is still pending.

### Wakers

A waker lets the executor know when a pending future is ready to make progress
again, so it can be polled without busy-waiting.

## Runtimes

Rust's standard library defines the `Future` trait but ships no executor; a
runtime such as Tokio or async-std provides one.

### Tasks

A task is a top-level future the runtime schedules and runs to completion,
independently of other tasks.

## Pitfalls

Blocking calls inside async code stall the executor thread. Keep blocking work
off the async path or hand it to a dedicated pool.
