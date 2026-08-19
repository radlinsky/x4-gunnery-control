import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const EXT_DIR = fileURLToPath(new URL(".", import.meta.url));
const REPO_ROOT = resolve(EXT_DIR, "..", "..");
const GUARD = join(REPO_ROOT, ".agents", "hooks", "shellcheck-disable-contract-guard.sh");

const normalizeLineEndings = s => s.replace(/\r\n/g, "\n").replace(/\r/g, "\n");

function resolveGuardArg(absPath) {
  const repoRootAbs = resolve(REPO_ROOT);
  if (absPath.startsWith(repoRootAbs + "/") || absPath === repoRootAbs) {
    return relative(repoRootAbs, absPath);
  }
  return absPath;
}

function probeGuard(guardArg) {
  const result = spawnSync(GUARD, [guardArg], {
    input: "# shellcheck disable=SC9999",
    encoding: "utf8",
    maxBuffer: 10 * 1024 * 1024,
  });
  if (result.error) return -1;
  return result.status;
}

function runGuard(guardArg, content) {
  const result = spawnSync(GUARD, [guardArg], {
    input: content,
    encoding: "utf8",
    maxBuffer: 10 * 1024 * 1024,
  });
  if (result.error) {
    return { block: true, reason: "could not safely inspect" };
  }
  if (result.status !== 0) {
    const reason = result.stderr?.trim() || "could not safely inspect edit target";
    return { block: true, reason };
  }
  return undefined;
}

export default function (pi) {
  pi.on("tool_call", (event, ctx) => {
    if (event.toolName === "write") {
      const input = event.input;
      if (
        !input ||
        typeof input.path !== "string" ||
        typeof input.content !== "string"
      ) {
        return { block: true, reason: "could not safely inspect write payload" };
      }

      let guardArg;
      try {
        const absPath = resolve(ctx.cwd, input.path);
        guardArg = resolveGuardArg(absPath);
      } catch {
        return { block: true, reason: "could not safely inspect write target" };
      }

      const result = runGuard(guardArg, input.content);
      if (result) return result;
      return undefined;
    }

    if (event.toolName === "edit") {
      const input = event.input;
      if (
        !input ||
        typeof input.path !== "string" ||
        !Array.isArray(input.edits) ||
        input.edits.length === 0
      ) {
        return { block: true, reason: "could not safely inspect edit payload" };
      }
      for (const edit of input.edits) {
        if (
          typeof edit.oldText !== "string" ||
          typeof edit.newText !== "string"
        ) {
          return { block: true, reason: "could not safely inspect edit payload" };
        }
      }

      let absPath;
      let guardArg;
      try {
        absPath = resolve(ctx.cwd, input.path);
        guardArg = resolveGuardArg(absPath);
      } catch {
        return { block: true, reason: "could not safely inspect" };
      }

      const probeStatus = probeGuard(guardArg);
      if (probeStatus === -1) {
        return { block: true, reason: "could not safely inspect" };
      }
      if (probeStatus === 0) {
        return undefined;
      }

      let currentContent;
      try {
        currentContent = readFileSync(absPath, "utf8");
      } catch {
        return { block: true, reason: "could not safely inspect" };
      }

      if (currentContent.charCodeAt(0) === 0xfeff) {
        currentContent = currentContent.slice(1);
      }
      const normalizedOriginal = normalizeLineEndings(currentContent);
      const normalizedEdits = input.edits.map(e => ({
        oldText: normalizeLineEndings(e.oldText),
        newText: normalizeLineEndings(e.newText),
      }));

      for (const edit of normalizedEdits) {
        if (edit.oldText.length === 0) {
          return { block: true, reason: "could not safely inspect edit payload" };
        }
        const regex = new RegExp(edit.oldText.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g');
        const matches = normalizedOriginal.match(regex);
        if (!matches || matches.length !== 1) {
          return { block: true, reason: "could not safely inspect edit payload" };
        }
      }

      const editMatches = normalizedEdits.map(edit => {
        const idx = normalizedOriginal.indexOf(edit.oldText);
        return {
          oldText: edit.oldText,
          newText: edit.newText,
          position: idx,
          end: idx + edit.oldText.length,
        };
      });

      editMatches.sort((a, b) => a.position - b.position);
      for (let i = 0; i < editMatches.length - 1; i++) {
        if (editMatches[i].end > editMatches[i + 1].position) {
          return { block: true, reason: "could not safely inspect edit payload" };
        }
      }

      editMatches.sort((a, b) => b.position - a.position);
      let reconstructed = normalizedOriginal;
      for (const match of editMatches) {
        reconstructed =
          reconstructed.slice(0, match.position) +
          match.newText +
          reconstructed.slice(match.end);
      }

      const result = runGuard(guardArg, reconstructed);
      if (result) return result;
      return undefined;
    }

    return undefined;
  });
}
