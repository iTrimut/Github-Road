// GitHub-Road — skills-only DSH plugin bundle.
// Minimal cordis plugin: the real content is the Agent Skill at skills/GitHub-Road/,
// which this plugin copies into ~/.dsh/skills/ on boot (mirrors dsh-webroad).
import { homedir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { existsSync, mkdirSync, readdirSync, statSync, copyFileSync } from 'node:fs';

const HERE = dirname(fileURLToPath(import.meta.url));
const SKILL_NAME = 'GitHub-Road';

function copyTree(src, dst) {
  mkdirSync(dst, { recursive: true });
  for (const entry of readdirSync(src)) {
    const from = join(src, entry);
    const to = join(dst, entry);
    if (statSync(from).isDirectory()) copyTree(from, to);
    else copyFileSync(from, to);
  }
}

export default {
  apply() {
    try {
      const dshHome = process.env.DSH_HOME || join(homedir(), '.dsh');
      const target = join(dshHome, 'skills', SKILL_NAME);
      const source = join(HERE, 'skills', SKILL_NAME);
      if (!existsSync(join(source, 'SKILL.md'))) return;
      if (existsSync(join(target, 'SKILL.md'))) return; // never overwrite user edits
      copyTree(source, target);
    } catch { /* best-effort, non-fatal */ }
  }
};
