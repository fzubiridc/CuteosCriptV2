#!/usr/bin/env node
// Stop hook — recordatorio NO bloqueante de mantener la memoria del repo al dia.
// Si tocaste codigo del juego (scripts/scenes/shaders/project.godot) sin actualizar docs/,
// inyecta un recordatorio UNA sola vez (respeta stop_hook_active para no loopear).
import { execSync } from "node:child_process";

// Lee stdin de forma robusta (readFileSync(0) falla con pipes en Windows).
function readStdin() {
  return new Promise((resolve) => {
    let data = "";
    const done = (v) => { clearTimeout(t); resolve(v); };
    const t = setTimeout(() => resolve(data), 300); // sin stdin -> no colgar
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (c) => (data += c));
    process.stdin.on("end", () => done(data));
    process.stdin.on("error", () => done(data));
  });
}

let raw = await readStdin();
if (raw.charCodeAt(0) === 0xfeff) raw = raw.slice(1); // strip BOM (PowerShell y otros lo prefijan)

let payload = {};
try {
  const clean = raw.trim();
  if (clean) payload = JSON.parse(clean);
} catch { /* payload vacio -> lo tratamos como tanda normal */ }

// Ya estamos en una continuacion disparada por este mismo hook -> no insistir (anti-loop).
if (payload.stop_hook_active) process.exit(0);

let status = "";
try {
  status = execSync("git status --porcelain", {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  }).trim();
} catch {
  process.exit(0); // no es repo git / git no disponible -> no-op
}

if (!status) process.exit(0); // working tree limpio

const paths = status.split(/\r?\n/).map((line) => {
  let p = line.slice(3).trim();
  if (p.includes(" -> ")) p = p.split(" -> ").pop(); // renames: nos quedamos con el destino
  return p.replace(/^"|"$/g, "");
});

const isGameCode = (p) =>
  /^(scripts|scenes|shaders)\//.test(p) ||
  p === "project.godot" ||
  /\.(gd|tscn|gdshader)$/.test(p);

const isMemory = (p) =>
  p.startsWith("docs/") || p === "AGENTS.md" || p === "CLAUDE.md";

const codeTouched = paths.some(isGameCode);
const memoryTouched = paths.some(isMemory);

if (codeTouched && !memoryTouched) {
  const reminder =
    "Recordatorio de memoria del repo: tocaste codigo del juego sin actualizar `docs/` en esta tanda. " +
    "Antes de cerrar, mira el `git status` y, SI el cambio altera el estado documentado, actualiza: " +
    "`docs/project_memory.md` (estado / decisiones / lista 'no tocar'), " +
    "el bloque \"Estado en una linea\" de `AGENTS.md`, y " +
    "`docs/architecture_notes.md` si cambio COMO funciona un sistema. " +
    "Si es trivial o no cambia nada documentado, decilo en una linea y cerra " +
    "-- no inventes updates ni toques los snapshots con fecha (code_audit / cleanup_candidates).";
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: { hookEventName: "Stop", additionalContext: reminder },
  }));
}
process.exit(0);
