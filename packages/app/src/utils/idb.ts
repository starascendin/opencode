import { checksum } from "@opencode-ai/util/encode"
import type { Message, Part, Session } from "@opencode-ai/sdk/v2/client"

const DB_NAME = "opencode"
const DB_VERSION = 1

const STORE_SESSIONS = "sessions"
const STORE_MESSAGES = "messages"
const STORE_PARTS = "parts"

function dirKey(dir: string) {
  const head = dir.slice(0, 12) || "workspace"
  const sum = checksum(dir) ?? "0"
  return `${head}.${sum}`
}

let dbPromise: Promise<IDBDatabase> | undefined

function open(): Promise<IDBDatabase> {
  if (dbPromise) return dbPromise
  dbPromise = new Promise<IDBDatabase>((resolve, reject) => {
    if (typeof indexedDB === "undefined") {
      reject(new Error("IndexedDB not available"))
      return
    }
    const request = indexedDB.open(DB_NAME, DB_VERSION)
    request.onupgradeneeded = () => {
      const db = request.result

      if (!db.objectStoreNames.contains(STORE_SESSIONS)) {
        db.createObjectStore(STORE_SESSIONS)
      }
      if (!db.objectStoreNames.contains(STORE_MESSAGES)) {
        db.createObjectStore(STORE_MESSAGES)
      }
      if (!db.objectStoreNames.contains(STORE_PARTS)) {
        db.createObjectStore(STORE_PARTS)
      }
    }
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => {
      dbPromise = undefined
      reject(request.error)
    }
  })
  return dbPromise
}

function tx(store: string, mode: IDBTransactionMode) {
  return open().then((db) => {
    const t = db.transaction(store, mode)
    return t.objectStore(store)
  })
}

function put<T>(store: string, key: string, value: T): Promise<void> {
  return tx(store, "readwrite").then(
    (os) =>
      new Promise<void>((resolve, reject) => {
        const req = os.put(value, key)
        req.onsuccess = () => resolve()
        req.onerror = () => reject(req.error)
      }),
  )
}

function get<T>(store: string, key: string): Promise<T | undefined> {
  return tx(store, "readonly").then(
    (os) =>
      new Promise<T | undefined>((resolve, reject) => {
        const req = os.get(key)
        req.onsuccess = () => resolve(req.result as T | undefined)
        req.onerror = () => reject(req.error)
      }),
  )
}

function del(store: string, key: string): Promise<void> {
  return tx(store, "readwrite").then(
    (os) =>
      new Promise<void>((resolve, reject) => {
        const req = os.delete(key)
        req.onsuccess = () => resolve()
        req.onerror = () => reject(req.error)
      }),
  )
}

function delRange(store: string, prefix: string): Promise<void> {
  return tx(store, "readwrite").then(
    (os) =>
      new Promise<void>((resolve, reject) => {
        const range = IDBKeyRange.bound(prefix, prefix + "\uffff")
        const req = os.delete(range)
        req.onsuccess = () => resolve()
        req.onerror = () => reject(req.error)
      }),
  )
}

// --- Sessions ---

function sessionKey(dir: string) {
  return `s:${dirKey(dir)}`
}

export function putSessions(dir: string, sessions: Session[]): Promise<void> {
  return put(STORE_SESSIONS, sessionKey(dir), sessions).catch(() => undefined)
}

export function getSessions(dir: string): Promise<Session[] | undefined> {
  return get<Session[]>(STORE_SESSIONS, sessionKey(dir)).catch(() => undefined)
}

export function deleteSessions(dir: string): Promise<void> {
  return del(STORE_SESSIONS, sessionKey(dir)).catch(() => undefined)
}

// --- Messages ---

function messageKey(dir: string, sessionID: string) {
  return `m:${dirKey(dir)}:${sessionID}`
}

export function putMessages(dir: string, sessionID: string, messages: Message[]): Promise<void> {
  return put(STORE_MESSAGES, messageKey(dir, sessionID), messages).catch(() => undefined)
}

export function getMessages(dir: string, sessionID: string): Promise<Message[] | undefined> {
  return get<Message[]>(STORE_MESSAGES, messageKey(dir, sessionID)).catch(() => undefined)
}

export function deleteMessages(dir: string, sessionID: string): Promise<void> {
  return del(STORE_MESSAGES, messageKey(dir, sessionID)).catch(() => undefined)
}

export function deleteAllMessages(dir: string): Promise<void> {
  return delRange(STORE_MESSAGES, `m:${dirKey(dir)}:`).catch(() => undefined)
}

// --- Parts ---

function partKey(dir: string, messageID: string) {
  return `p:${dirKey(dir)}:${messageID}`
}

export function putParts(dir: string, messageID: string, parts: Part[]): Promise<void> {
  return put(STORE_PARTS, partKey(dir, messageID), parts).catch(() => undefined)
}

export function getParts(dir: string, messageID: string): Promise<Part[] | undefined> {
  return get<Part[]>(STORE_PARTS, partKey(dir, messageID)).catch(() => undefined)
}

export function deleteParts(dir: string, messageID: string): Promise<void> {
  return del(STORE_PARTS, partKey(dir, messageID)).catch(() => undefined)
}

export function deleteAllParts(dir: string): Promise<void> {
  return delRange(STORE_PARTS, `p:${dirKey(dir)}:`).catch(() => undefined)
}

// --- Bulk cleanup for a session ---

export async function deleteSessionData(dir: string, sessionID: string, messageIDs: string[]): Promise<void> {
  await deleteMessages(dir, sessionID)
  await Promise.all(messageIDs.map((id) => deleteParts(dir, id)))
}

// --- Bulk cleanup for an entire directory ---

export async function deleteDirectoryData(dir: string): Promise<void> {
  await Promise.all([deleteSessions(dir), deleteAllMessages(dir), deleteAllParts(dir)])
}
