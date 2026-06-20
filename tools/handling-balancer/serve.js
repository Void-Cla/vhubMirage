#!/usr/bin/env node
// serve.js — atalho para subir a interface web (mesmo que `node balance.js serve`)
//
// Uso: node serve.js [--port 7920]

const server = require('./lib/server');

const args = process.argv.slice(2);
const portIdx = args.indexOf('--port');
const port = portIdx >= 0 ? parseInt(args[portIdx + 1], 10) : 7920;

server.start(port);
