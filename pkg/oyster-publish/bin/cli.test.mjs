import path from "node:path";
import { describe, expect, test } from "vitest";
import { commandEnvironment, createProgram } from "./cli.mjs";

async function parse(args) {
  let parsed;
  const program = createProgram((command) => {
    parsed = command;
  });
  program.exitOverride();
  program.configureOutput({ writeOut() {}, writeErr() {} });
  for (const command of program.commands) {
    command.exitOverride();
    command.configureOutput({ writeOut() {}, writeErr() {} });
  }
  await program.parseAsync(args, { from: "user" });
  return parsed;
}

describe("oyster-publish CLI", () => {
  test("parses publishing options and forwards arguments after --", async () => {
    await expect(
      parse([
        "dev",
        "-v",
        "notes",
        "--published-only",
        "--title",
        "Garden",
        "--no-ancestor-initials",
        "--",
        "--host",
        "0.0.0.0",
      ]),
    ).resolves.toMatchInlineSnapshot(`
      {
        "ancestorInitials": false,
        "astroArgs": [
          "--host",
          "0.0.0.0",
        ],
        "command": "dev",
        "favicon": undefined,
        "publishedOnly": true,
        "target": "./dist",
        "title": "Garden",
        "vault": "notes",
      }
    `);
  });

  test("supports --out-dir as a target alias", async () => {
    await expect(
      parse(["build", "-v", "notes", "--out-dir", "site"]),
    ).resolves.toMatchObject({ target: "site" });
  });

  test("requires a known command and a vault", async () => {
    await expect(parse(["preview"])).rejects.toMatchInlineSnapshot(`[CommanderError: error: unknown command 'preview']`);
    await expect(parse(["build"])).rejects.toMatchInlineSnapshot(`[CommanderError: error: required option '-v, --vault <path>' not specified]`);
  });

  test("creates resolved, minimal environment overrides", async () => {
    const parsed = await parse(["build", "-v", "notes", "-o", "site"]);
    expect(commandEnvironment(parsed, "/work")).toMatchInlineSnapshot(`
      {
        "OYSTER_OUT_DIR": "/work/site",
        "OYSTER_PUBLISHED_ONLY": "0",
        "OYSTER_VAULT": "/work/notes",
      }
    `);
  });
});
