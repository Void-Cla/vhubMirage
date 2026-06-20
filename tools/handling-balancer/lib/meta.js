// meta.js — parsing e substituicao CIRURGICA de handling.meta
//
// Este e o ponto mais perigoso do pipeline (script.md §6). NAO usamos round-trip de XML
// (xml2js Parser->Builder reescreveria o arquivo inteiro: reordena atributos, destroi
// <Item type="NULL"/>, remove comentarios, muda formatacao). Em vez disso:
//
//   - dividimos o arquivo nos blocos <Item type="CHandlingData"> ... </Item> de TOPO
//     (ignorando os <Item> aninhados dentro de <SubHandlingData>);
//   - dentro de cada bloco, trocamos APENAS o conteudo de value="..." dos campos-alvo;
//   - todo o resto do arquivo permanece byte-a-byte identico.
//
// Os 3 .meta reais provam que isso e obrigatorio: formatacoes divergentes (value="0",
// value="180.094", value="1.20000", indentacao com TAB), sem trailing newline na supra.

const norm = require('./util').norm;
const f6   = require('./util').f6;


// ============================================================
// SPLIT EM BLOCOS DE TOPO
// ============================================================

// divide o arquivo em segmentos, marcando quais sao blocos <Item type="CHandlingData">.
// devolve [{ text, isHandling }] cuja concatenacao reproduz o arquivo original exato.
function splitBlocks(content) {
  const segments = [];
  const open = /<Item\s+type="CHandlingData"\s*>/g;
  let cursor = 0;
  let m;

  while ((m = open.exec(content)) !== null) {
    const blockStart = m.index;
    const closeIdx = findMatchingClose(content, open.lastIndex);
    if (closeIdx === -1) break; // arquivo malformado: para de fatiar (resto vira prefixo)

    // tudo entre o cursor e o inicio do bloco = segmento inalteravel (prefixo/entre-blocos)
    if (blockStart > cursor) {
      segments.push({ text: content.slice(cursor, blockStart), isHandling: false });
    }
    // o bloco em si (da abertura ao fim de </Item>)
    segments.push({ text: content.slice(blockStart, closeIdx), isHandling: true });
    cursor = closeIdx;
    open.lastIndex = closeIdx;
  }

  // sufixo final inalteravel
  if (cursor < content.length) {
    segments.push({ text: content.slice(cursor), isHandling: false });
  }
  return segments;
}

// a partir do fim da tag de abertura, acha o indice logo apos o </Item> correspondente,
// contando aninhamento de <Item ...> (SubHandlingData tem <Item type="CCarHandlingData">
// e <Item type="NULL"/>, este ultimo self-closing nao conta como aninhamento).
function findMatchingClose(content, fromIdx) {
  const token = /<Item\b[^>]*?(\/?)>|<\/Item>/g;
  token.lastIndex = fromIdx;
  let depth = 1;
  let m;

  while ((m = token.exec(content)) !== null) {
    if (m[0] === '</Item>') {
      depth -= 1;
      if (depth === 0) return token.lastIndex; // fim do bloco de topo
    } else if (m[1] !== '/') {
      // <Item ...> de abertura (nao self-closing) — aninha
      depth += 1;
    }
    // m[1] === '/' => self-closing (<Item type="NULL"/>) — nao altera profundidade
  }
  return -1;
}


// ============================================================
// LEITURA DE CAMPOS DENTRO DE UM BLOCO
// ============================================================

// extrai o handlingName normalizado do bloco (UPPERCASE+trim); nil se ausente
function readHandlingName(block) {
  const m = block.match(/<handlingName>\s*([^<]+?)\s*<\/handlingName>/);
  return m ? norm(m[1]) : null;
}

// le o valor numerico de <field value="..."/>; NaN se ausente/invalido
function readValue(block, field) {
  const m = block.match(new RegExp(`<${field}\\s+value="([^"]*)"`));
  return m ? parseFloat(m[1]) : NaN;
}

// le um atributo de uma tag-vetor (ex.: z de vecInertiaMultiplier); NaN se ausente
function readAttr(block, tag, attr) {
  const m = block.match(new RegExp(`<${tag}\\b[^>]*?\\b${attr}="([^"]*)"`));
  return m ? parseFloat(m[1]) : NaN;
}


// ============================================================
// ESCRITA CIRURGICA DENTRO DE UM BLOCO
// ============================================================

// substitui o conteudo de value="..." de um campo, preservando indentacao e formato.
// devolve { block, changed, missing }. Nao grava nada se o valor ja for igual (diff limpo).
function setValue(block, field, num) {
  const re = new RegExp(`(<${field}\\s+value=")([^"]*)("\\s*/>)`);
  const m = block.match(re);
  if (!m) return { block, changed: false, missing: true };

  const next = f6(num);
  if (m[2] === next) return { block, changed: false, missing: false }; // ja esta no alvo

  return { block: block.replace(re, `$1${next}$3`), changed: true, missing: false };
}


module.exports = {
  splitBlocks,
  readHandlingName,
  readValue,
  readAttr,
  setValue,
};
