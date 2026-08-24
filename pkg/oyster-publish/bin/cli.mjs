import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { Command } from "commander";

const packageRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const packageJson = JSON.parse(
  fs.readFileSync(path.join(packageRoot, "package.json"), "utf8"),
);

function publishingCommand(name, description, onCommand) {
  return new Command(name)
    .description(description)
    .requiredOption("-v, --vault <path>", "vault directory to publish")
    .option("-o, --target <path>", "output directory", "./dist")
    .option("--out-dir <path>", "alias for --target")
    .option("--published-only", "include only notes with publish: true")
    .option("--title <name>", "override the configured site name")
    .option("--favicon <url>", "override the configured favicon URL")
    .option("--no-ancestor-initials", "show ancestor folder names in full")
    .argument("[astro-options...]", "Astro options, placed after --")
    .action((astroArgs, values) => {
      return onCommand({
        command: name,
        vault: values.vault,
        target: values.outDir ?? values.target,
        publishedOnly: values.publishedOnly ?? false,
        title: values.title,
        favicon: values.favicon,
        ancestorInitials: values.ancestorInitials === false ? false : undefined,
        astroArgs,
      });
    });
}

export function createProgram(onCommand = executeCommand) {
  const program = new Command()
    .name("oyster-publish")
    .description("Publish an Obsidian vault as a static site.")
    .version(packageJson.version)
    .showHelpAfterError()
    .addHelpText(
      "after",
      '\nRun "oyster-publish <command> --help" for command options.',
    );

  program.addCommand(
    publishingCommand("build", "build the site into a directory", onCommand),
  );
  program.addCommand(
    publishingCommand("dev", "start a local development server", onCommand),
  );
  return program;
}

export function commandEnvironment(parsed, cwd = process.cwd()) {
  return {
    OYSTER_VAULT: path.resolve(cwd, parsed.vault),
    OYSTER_OUT_DIR: path.resolve(cwd, parsed.target),
    OYSTER_PUBLISHED_ONLY: parsed.publishedOnly ? "1" : "0",
    ...(parsed.title ? { OYSTER_SITE_TITLE: parsed.title } : {}),
    ...(parsed.favicon ? { OYSTER_SITE_FAVICON: parsed.favicon } : {}),
    ...(parsed.ancestorInitials === false
      ? { OYSTER_SITE_ANCESTOR_INITIALS: "0" }
      : {}),
  };
}

function findAstroCli() {
  const require = createRequire(import.meta.url);
  const packagePath = require.resolve("astro/package.json");
  const astroPackage = JSON.parse(fs.readFileSync(packagePath, "utf8"));
  return path.resolve(path.dirname(packagePath), astroPackage.bin.astro);
}

export function executeCommand(parsed) {
  const env = commandEnvironment(parsed);
  if (!fs.existsSync(env.OYSTER_VAULT) || !fs.statSync(env.OYSTER_VAULT).isDirectory()) {
    throw new Error(`vault is not a directory: ${env.OYSTER_VAULT}`);
  }

  return new Promise((resolve, reject) => {
    const child = spawn(
      process.execPath,
      [findAstroCli(), parsed.command, ...parsed.astroArgs],
      {
        cwd: packageRoot,
        env: { ...process.env, ...env },
        stdio: "inherit",
      },
    );
    child.on("error", reject);
    child.on("exit", (code, signal) => {
      if (signal) process.kill(process.pid, signal);
      else if (code === 0) resolve();
      else reject(new Error(`Astro exited with status ${code ?? 1}`));
    });
  });
}

export async function run(argv = process.argv) {
  try {
    await createProgram().parseAsync(argv);
  } catch (error) {
    console.error(`oyster-publish: ${error.message}`);
    process.exitCode = 1;
  }
}
