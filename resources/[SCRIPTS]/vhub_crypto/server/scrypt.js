// scrypt.js — KDF server-only, sem dependencia externa.

'use strict';

const crypto = require('node:crypto');

const PARAMS = Object.freeze({ N: 32768, r: 8, p: 3, keylen: 32 });
const MAX_MEMORY = 64 * 1024 * 1024;
const MAX_ACTIVE = 4;
const MAX_QUEUE = 128;
const FORMAT = /^\$scrypt\$v=1\$N=(\d+),r=(\d+),p=(\d+)\$([0-9a-f]{32})\$([0-9a-f]{64})$/;

function normalizeInput(password, pepper) {
  if (typeof password !== 'string' || Buffer.byteLength(password, 'utf8') > 256) {
    throw new Error('senha_invalida');
  }
  if (typeof pepper !== 'string' || pepper.length < 32 || pepper.length > 512) {
    throw new Error('pepper_invalido');
  }
  return crypto.createHmac('sha256', pepper).update(password, 'utf8').digest();
}

function derive(password, pepper, salt, params = PARAMS) {
  const secret = normalizeInput(password, pepper);
  return new Promise((resolve, reject) => {
    crypto.scrypt(secret, salt, params.keylen, {
      N: params.N,
      r: params.r,
      p: params.p,
      maxmem: MAX_MEMORY,
    }, (error, key) => {
      secret.fill(0);
      if (error) reject(error);
      else resolve(key);
    });
  });
}

async function hashPassword(password, pepper) {
  const salt = crypto.randomBytes(16);
  const key = await derive(password, pepper, salt);
  return `$scrypt$v=1$N=${PARAMS.N},r=${PARAMS.r},p=${PARAMS.p}`
    + `$${salt.toString('hex')}$${key.toString('hex')}`;
}

async function verifyPassword(password, pepper, encoded) {
  if (typeof encoded !== 'string' || encoded.length > 255) {
    return { valid: false, rehash: false, error: 'hash_malformado' };
  }
  const match = FORMAT.exec(encoded);
  if (!match) return { valid: false, rehash: false, error: 'hash_malformado' };

  const params = {
    N: Number(match[1]),
    r: Number(match[2]),
    p: Number(match[3]),
    keylen: 32,
  };
  if (!Number.isSafeInteger(params.N) || params.N < 2 || params.N > PARAMS.N
      || (params.N & (params.N - 1)) !== 0
      || !Number.isSafeInteger(params.r) || params.r < 1 || params.r > 32
      || !Number.isSafeInteger(params.p) || params.p < 1 || params.p > 16) {
    return { valid: false, rehash: false, error: 'parametros_invalidos' };
  }

  const expected = Buffer.from(match[5], 'hex');
  const actual = await derive(password, pepper, Buffer.from(match[4], 'hex'), params);
  const valid = expected.length === actual.length && crypto.timingSafeEqual(expected, actual);
  const rehash = valid && (params.N !== PARAMS.N || params.r !== PARAMS.r || params.p !== PARAMS.p);
  expected.fill(0);
  actual.fill(0);
  return { valid, rehash, error: valid ? null : 'senha_incorreta' };
}

function installBridge() {
  if (typeof on !== 'function' || typeof emit !== 'function'
      || typeof GetCurrentResourceName !== 'function') return;

  const channel = `__vhub_crypto:${GetCurrentResourceName()}`;
  const queue = [];
  let active = 0;

  function respond(id, ok, value, elapsedMs) {
    setImmediate(() => emit(`${channel}:response`, id, ok, value, elapsedMs));
  }

  function drain() {
    while (active < MAX_ACTIVE && queue.length > 0) {
      const job = queue.shift();
      active += 1;
      const started = process.hrtime.bigint();
      const operation = job.op === 'hash'
        ? hashPassword(job.password, job.pepper)
        : verifyPassword(job.password, job.pepper, job.encoded);

      operation.then((value) => {
        const elapsed = Number(process.hrtime.bigint() - started) / 1e6;
        respond(job.id, true, value, elapsed);
      }).catch((error) => {
        const elapsed = Number(process.hrtime.bigint() - started) / 1e6;
        const code = error && error.message === 'pepper_invalido'
          ? 'pepper_invalido' : 'kdf_indisponivel';
        respond(job.id, false, code, elapsed);
      }).finally(() => {
        active -= 1;
        drain();
      });
    }
  }

  on(`${channel}:request`, (id, op, password, pepper, encoded) => {
    if (typeof id !== 'string' || !/^[a-zA-Z0-9:_-]{1,96}$/.test(id)
        || (op !== 'hash' && op !== 'verify')) return;
    if (active + queue.length >= MAX_ACTIVE + MAX_QUEUE) {
      respond(id, false, 'fila_cheia', 0);
      return;
    }
    queue.push({ id, op, password, pepper, encoded });
    drain();
  });
}

installBridge();

module.exports = { PARAMS, hashPassword, verifyPassword };
