import { mkdir, readFile, rm, writeFile } from "node:fs/promises"
import { dirname, join } from "node:path"

const root = process.cwd()
const out = join(root, "www")
const base = process.env.OPENCODE_SPA_URL ?? "https://vps-60d9e960.tail05d28.ts.net:4096"
const api = process.env.VITE_OPENCODE_SERVER_URL ?? "https://vps-60d9e960.tail05d28.ts.net:4096"
const seen = new Set()
const queue = ["/"]

await rm(out, { recursive: true, force: true })
await mkdir(out, { recursive: true })

const norm = (raw, from = "/") => {
  if (!raw) return
  const url = raw.trim().replace(/^["']|["']$/g, "")
  if (!url || url.startsWith("data:") || url.startsWith("#")) return
  if (
    !url.startsWith("/") &&
    !url.startsWith("./") &&
    !url.startsWith("../") &&
    !url.startsWith("http://") &&
    !url.startsWith("https://")
  ) {
    return
  }
  const parsed = new URL(url, new URL(from, base))
  if (parsed.origin !== new URL(base).origin) return
  return `${parsed.pathname}${parsed.search}`
}

const refs = (text, from) => {
  const out = new Set()
  const push = (x) => {
    const value = norm(x, from)
    if (!value) return
    out.add(value)
  }
  for (const match of text.matchAll(/(?:src|href)=["']([^"']+)["']/g)) push(match[1])
  for (const match of text.matchAll(/url\(([^)]+)\)/g)) push(match[1])
  for (const match of text.matchAll(/(?:import\(|from\s*)["'`]([^"'`]+)["'`]/g)) push(match[1])
  for (const match of text.matchAll(/["'`](\/assets\/[^"'` )]+)["'`]/g)) push(match[1])
  return [...out]
}

while (queue.length > 0) {
  const path = queue.shift()
  if (!path || seen.has(path)) continue
  seen.add(path)
  const url = `${base}${path}`
  const res = await fetch(url)
  if (!res.ok) throw new Error(`failed to fetch ${url}: ${res.status}`)
  const type = (res.headers.get("content-type") ?? "").toLowerCase()
  const file = path === "/" ? "/index.html" : path
  const target = join(out, file.replace(/^\//, ""))
  await mkdir(dirname(target), { recursive: true })

  if (type.includes("text/html")) {
    let html = await res.text()
    if (file === "/index.html") {
      const script =
        "<script>try{localStorage.setItem('opencode.settings.dat:defaultServerUrl','" +
        api +
        "')}catch{}</script>"
      html = html.includes("</head>") ? html.replace("</head>", `${script}</head>`) : `${script}${html}`
    }
    await writeFile(target, html)
    refs(html, path).forEach((item) => {
      if (!seen.has(item)) queue.push(item)
    })
    continue
  }

  if (type.includes("javascript") || type.includes("css") || type.includes("json") || type.includes("text/")) {
    const text = await res.text()
    await writeFile(target, text)
    refs(text, path).forEach((item) => {
      if (!seen.has(item)) queue.push(item)
    })
    continue
  }

  const bytes = Buffer.from(await res.arrayBuffer())
  await writeFile(target, bytes)
}

const html = await readFile(join(out, "index.html"), "utf8")
if (!html.includes("opencode.settings.dat:defaultServerUrl")) {
  throw new Error("index bootstrap missing server url")
}

console.log(`mirrored ${seen.size} paths into ${out}`)
