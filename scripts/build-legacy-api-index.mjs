#!/usr/bin/env node

import { readFile, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";

if (process.argv.length !== 3) {
  console.error("usage: node scripts/build-legacy-api-index.mjs <api-directory>");
  process.exit(2);
}

const root = resolve(process.argv[2]);
const index = await readFile(join(root, "index.html"), "utf8");
const entries = [];
const seen = new Set();
const compilationUnits = index.split("<h2 id=tagged-types>")[0];
const links = compilationUnits.matchAll(
  /<a\s+href=([^\s>#]+\.html)\s+target=document-content>([^<]+)<\/a>/g,
);

for (const match of links) {
  const href = match[1];
  const name = match[2];
  if (seen.has(name)) continue;
  seen.add(name);
  entries.push({ name, qualifiedName: name, kind: "Compilation unit", href });

  const page = await readFile(join(root, href), "utf8");
  const entities = [...page.matchAll(/<h4\s+id=([^\s>]+)>([^<]+)<\/h4>/g)];
  for (let entityPosition = 0; entityPosition < entities.length; entityPosition += 1) {
    const entity = entities[entityPosition];
    const entityName = entity[2].replaceAll("&quot;", '"');
    const nextEntity = entities[entityPosition + 1];
    const section = page.slice(entity.index, nextEntity?.index ?? page.length);
    const isSubprogram = /<pre\s+class=ada-code-snippet><code>\s*(function|procedure)\b/.test(
      section,
    );
    entries.push({
      name: entityName,
      qualifiedName: `${name}.${entityName}`,
      kind: isSubprogram ? "Subprogram" : "API entity",
      href: `${href}#${entity[1]}`,
    });

    const literalBlock = section.match(/<h5>Enumeration Literal<\/h5><dl>([\s\S]*?)<\/dl>/);
    if (literalBlock === null) continue;

    for (const literal of literalBlock[1].matchAll(/<dt>([^<]+)<dd>/g)) {
      entries.push({
        name: literal[1],
        qualifiedName: `${name}.${literal[1]}`,
        kind: "Enumeration literal",
        href: `${href}#${entity[1]}`,
      });
    }
  }
}

if (seen.size === 0) throw new Error("GNATdoc index contains no compilation units");
entries.sort((left, right) => left.qualifiedName.localeCompare(right.qualifiedName));
await writeFile(
  join(root, "search-index.js"),
  `window.FlyologyApiSearch = ${JSON.stringify(entries)};\n`,
);
console.log(
  `GNATdoc compatibility index generated: ${entries.length} names from ${seen.size} units.`,
);
