#!/usr/bin/env node
// balance.js — entrypoint do vHub Handling Balancer (pipeline offline)
//
// Parseia args, carrega+valida config e despacha para o comando. SEM regra de negocio
// aqui — so orquestracao e mapeamento de exit codes:
//   0 ok  ·  1 drift/divergencia (verify)  ·  2 erro de config  ·  3 erro de I/O
//
// Uso:
//   node balance.js scan
//   node balance.js plan   [--only A80,SKYLINE] [--tier A] [--json]
//   node balance.js apply  [--dry-run] [--only ...] [--tier ...] [--no-backup --force]
//   node balance.js verify [--json]
//   node balance.js seal
//   node balance.js restore [--backup <id>]

const config = require('./lib/config');
const { log } = require('./lib/report');

// registro de comandos (cada um exporta { run(args, cfg) -> exitCode, describe })
const COMMANDS = {
  scan:    require('./commands/scan'),
  plan:    require('./commands/plan'),
  apply:   require('./commands/apply'),
  verify:  require('./commands/verify'),
  seal:    require('./commands/seal'),
  restore: require('./commands/restore'),
  serve:   require('./commands/serve'),
};


// ============================================================
// PARSE DE ARGUMENTOS
// ============================================================

// separa o comando dos flags. flags booleanos (--dry-run) ou com valor (--tier A).
function parse(argv) {
  const [cmd, ...rest] = argv;
  const args = {};

  for (let i = 0; i < rest.length; i++) {
    const tok = rest[i];
    if (!tok.startsWith('--')) continue;
    const key = tok.slice(2);
    const next = rest[i + 1];
    if (next !== undefined && !next.startsWith('--')) {
      args[key] = next;
      i += 1;
    } else {
      args[key] = true;
    }
  }
  return { cmd, args };
}


// ============================================================
// AJUDA
// ============================================================

function usage() {
  console.log('vHub Handling Balancer — pipeline offline de balanceamento de handling.meta\n');
  console.log('Uso: node balance.js <comando> [flags]\n');
  console.log('Comandos:');
  for (const [name, mod] of Object.entries(COMMANDS)) {
    console.log(`  ${name.padEnd(9)} ${mod.describe}`);
  }
  console.log('\nFlags: --dry-run --only <names> --tier <D..S+> --json --backup <id> ' +
              '--no-backup --force');
  console.log('Exit codes: 0 ok | 1 drift | 2 erro de config | 3 erro de I/O');
}


// ============================================================
// MAIN
// ============================================================

function main() {
  const { cmd, args } = parse(process.argv.slice(2));

  if (!cmd || cmd === 'help' || cmd === '--help' || cmd === '-h') {
    usage();
    return 0;
  }

  const command = COMMANDS[cmd];
  if (!command) {
    log.erro(`comando desconhecido: "${cmd}"`);
    usage();
    return 2;
  }

  // config so e exigida por comandos que a usam.
  // restore = por backup id; serve = carrega config fresca por request (dentro do server).
  let cfg = null;
  if (cmd !== 'restore' && cmd !== 'serve') {
    cfg = config.load(); // ConfigError -> exit 2 (capturado abaixo)
  }

  return command.run(args, cfg);
}


// ============================================================
// EXECUCAO + MAPEAMENTO DE EXIT CODE
// ============================================================

try {
  const result = main();
  // comandos long-running (serve) sinalizam keepAlive: nao encerrar o processo
  if (result && typeof result === 'object' && result.keepAlive) {
    // servidor segue escutando; sem process.exit
  } else {
    process.exit(typeof result === 'number' ? result : 0);
  }
} catch (e) {
  if (e instanceof config.ConfigError) {
    log.erro(e.message);
    process.exit(2);
  }
  if (e && e.exitCode) {          // IoError (3) e afins
    log.erro(e.message);
    process.exit(e.exitCode);
  }
  // erro inesperado: stack completa + exit 3 (I/O e o balde mais provavel)
  log.erro(`erro inesperado: ${e && e.message}`);
  if (process.env.DEBUG) console.error(e);
  process.exit(3);
}
