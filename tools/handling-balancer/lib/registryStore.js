// registryStore.js — leitura/escrita de config/registry.json (decisões persistidas pela UI)
//
// A UI é um editor amigável do registry.json: ao confirmar o tier de um carro, persistimos
// aqui (fonte única de verdade que o CLI também usa). Ao renomear, migramos a chave.

const path = require('path');
const io   = require('./io');
const { norm } = require('./util');

const REGISTRY_PATH = path.join(io.TOOL_ROOT, 'config', 'registry.json');


// lê o registry.json bruto (com _doc e vehicles)
function read() {
  const reg = io.readJson(REGISTRY_PATH);
  reg.vehicles = reg.vehicles || {};
  return reg;
}

// grava o registry.json (preserva _doc; mantém ordem de chaves)
function write(reg) {
  io.writeJson(REGISTRY_PATH, reg);
}

// define/atualiza o tier de um carro (chave = handlingName normalizado UPPER)
function setTier(handlingName, tierBase, tierMax) {
  const reg = read();
  const key = norm(handlingName);
  reg.vehicles[key] = { tier_base: tierBase, tier_max: tierMax || tierBase };
  write(reg);
  return reg.vehicles[key];
}

// migra a entrada do registry quando o carro é renomeado (oldName -> newName)
function migrateKey(oldName, newName) {
  const reg = read();
  const o = norm(oldName);
  const n = norm(newName);
  if (reg.vehicles[o] && o !== n) {
    reg.vehicles[n] = reg.vehicles[o];
    delete reg.vehicles[o];
    write(reg);
  }
}

// remove uma entrada (uso administrativo)
function remove(handlingName) {
  const reg = read();
  delete reg.vehicles[norm(handlingName)];
  write(reg);
}


module.exports = { read, write, setTier, migrateKey, remove, REGISTRY_PATH };
