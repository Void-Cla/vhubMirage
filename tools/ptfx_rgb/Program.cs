using CodeWalker.GameFiles;
using CodeWalker.Utils;
using System.Xml;
using System.Xml.Linq;
using System.Security.Cryptography;
using System.Globalization;
using System.IO.Compression;

// Conversor offline; nunca carregado pelo FXServer. Origens são preservadas.
if (args.Length == 6 && args[0] == "gerar")
{
    Gerar(args[1], args[2], args[3], args[4], args[5]);
    return;
}
if (args.Length != 3 || args[0] != "inspecionar")
    throw new ArgumentException("Uso: inspecionar <origem.ypt> <pasta-exportacao> | gerar <origem.ypt.xml> <reserva.ypt.xml> <efeito> <dicionario> <pasta-nova>");
var origem = Path.GetFullPath(args[1]);
var destino = Path.GetFullPath(args[2]);
if (File.Exists(destino) || Directory.Exists(destino))
    throw new IOException("A pasta de exportação deve ser nova.");
var info = new FileInfo(origem);
if (!info.Exists || info.Length < 16 || info.Length > 16 * 1024 * 1024)
    throw new InvalidDataException("Origem ausente ou fora do limite de 16 MiB.");
var dados = File.ReadAllBytes(origem);
if (BitConverter.ToUInt32(dados, 0) != 0x37435352 || BitConverter.ToUInt32(dados, 4) != 68)
    throw new InvalidDataException("Esperado RSC7 versão 68 (GTA Legacy).");
// Limita a expansão antes de entregar o recurso ao parser de terceiros.
using (var comprimido = new MemoryStream(dados, 16, dados.Length - 16))
using (var inflador = new DeflateStream(comprimido, CompressionMode.Decompress))
{
    var buffer = new byte[65536]; long expandido = 0; int lidos;
    while ((lidos = inflador.Read(buffer)) != 0)
    {
        expandido += lidos;
        if (expandido > 64 * 1024 * 1024) throw new InvalidDataException("Recurso expandido excede 64 MiB.");
    }
}
var ypt = new YptFile();
ypt.Load(dados);
if (!string.IsNullOrEmpty(ypt.ErrorMessage) || ypt.PtfxList == null)
    throw new InvalidDataException(ypt.ErrorMessage ?? "Dicionário de partículas ausente.");
Console.WriteLine($"Dicionário: {ypt.PtfxList.Name?.Value}");
foreach (var efeito in ypt.AllEffects ?? [])
    Console.WriteLine($"Efeito: {efeito.Name?.Value}");
Directory.CreateDirectory(destino);
File.WriteAllText(Path.Combine(destino, "origem.ypt.xml"), YptXml.GetXml(ypt, destino));
Console.WriteLine($"Exportado: {destino}");

static XDocument LerXml(string caminho)
{
    if (new FileInfo(caminho).Length > 64 * 1024 * 1024) throw new InvalidDataException("XML excede 64 MiB.");
    using var reader = XmlReader.Create(caminho, new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null });
    return XDocument.Load(reader);
}

static Dictionary<string, XElement> Indice(XElement raiz, string dicionario) =>
    (raiz.Element(dicionario)?.Elements("Item") ?? []).ToDictionary(n => n.Element("Name")!.Value, StringComparer.Ordinal);

static void Gerar(string xmlOrigem, string xmlTexturas, string efeito, string nome, string destino)
{
    if (nome is not ("mirage_backfire_rgb" or "mirage_nitrous_rgb")) throw new ArgumentException("Dicionário não permitido.");
    xmlOrigem = Path.GetFullPath(xmlOrigem); xmlTexturas = Path.GetFullPath(xmlTexturas); destino = Path.GetFullPath(destino);
    if (Directory.Exists(destino) || File.Exists(destino)) throw new IOException("Destino deve ser novo.");
    var doc = LerXml(xmlOrigem); var raiz = doc.Root!;
    var efeitos = Indice(raiz, "EffectRuleDictionary"); var particulas = Indice(raiz, "ParticleRuleDictionary");
    var emissores = Indice(raiz, "EmitterRuleDictionary");
    var calibradas = new List<(string Dicionario, string Regra, string Nome)>();
    XElement? eventoChama = null;
    var efUsados = new HashSet<string>(); var ptUsadas = new HashSet<string>(); var emUsados = new HashSet<string>();
    void VisitarEfeito(string id)
    {
        if (!efUsados.Add(id)) return;
        if (efUsados.Count > 32 || !efeitos.TryGetValue(id, out var ef)) throw new InvalidDataException("Referência de efeito inválida.");
        foreach (var evento in ef.Element("EventEmitters")?.Elements("Item") ?? [])
        {
            var em = evento.Element("EmitterRule")?.Value ?? "";
            if (!emissores.ContainsKey(em)) throw new InvalidDataException($"Emissor ausente: {em}");
            emUsados.Add(em);
            var pt = evento.Element("ParticleRule")?.Value ?? "";
            if (!particulas.TryGetValue(pt, out var regra)) throw new InvalidDataException($"Partícula ausente: {pt}");
            if (!ptUsadas.Add(pt)) continue;
            foreach (var refEf in regra.Descendants("EffectRule").Where(n => !string.IsNullOrEmpty(n.Value))) VisitarEfeito(refEf.Value);
            if (regra.Descendants("Drawables").Any(n => n.HasElements)) throw new InvalidDataException("Drawable não suportado neste extrator de sprites.");
        }
    }
    VisitarEfeito(efeito);
    foreach (var (dict, manter) in new[] { ("EffectRuleDictionary", efUsados), ("ParticleRuleDictionary", ptUsadas), ("EmitterRuleDictionary", emUsados) })
        foreach (var item in raiz.Element(dict)!.Elements("Item").ToArray()) if (!manter.Contains(item.Element("Name")!.Value)) item.Remove();
    raiz.Element("DrawableDictionary")?.Remove();
    raiz.Element("Name")!.Value = nome;
    efeitos[efeito].Element("Name")!.Value = "chama_rgb";
    // Referências ao efeito raiz são atualizadas, nunca aos efeitos globais de outros dicionários.
    foreach (var referencia in raiz.Descendants("EffectRule").Where(n => n.Value == efeito)) referencia.Value = "chama_rgb";
    // O efeito nitrous original é contínuo. A integração existente usa pulsos não-loopados.
    efeitos[efeito].Element("NumLoops")!.SetAttributeValue("value", "0x0");
    efeitos[efeito].Element("IsShortLived")!.SetAttributeValue("value", "1");
    // Zoom KFP é percentual: 1 representa 1%, NÃO um multiplicador neutro.
    // Mantém o perfil já calibrado de glow/haze/fumaça; compensação da chama abaixo.
    foreach (var prop in efeitos[efeito].Descendants("Item").Where(n => n.Element("Name")?.Value == "ptxEffectRule:m_zoomScalarKFP"))
        foreach (var valor in prop.Descendants("KeyframeValue"))
        {
            valor.SetAttributeValue("x", "1"); valor.SetAttributeValue("y", "1");
        }

    if (nome == "mirage_backfire_rgb")
    {
        // Calibra somente a chama. Glow/haze/fumaça, densidade, alpha e zoom raiz ficam intactos.
        void Calibrar(string dicionario, string id, XElement regra, string propriedade, decimal fator)
        {
            var curva = regra.Descendants().Single(n => n.Element("Name")?.Value == propriedade);
            var valores = curva.Descendants("KeyframeValue").ToArray();
            if (valores.Length == 0) throw new InvalidDataException($"Curva vazia: {propriedade}");
            foreach (var valor in valores)
                foreach (var eixo in new[] { "x", "y" })
                {
                    var numero = decimal.Parse(valor.Attribute(eixo)!.Value, CultureInfo.InvariantCulture) * fator;
                    if (numero < 0 || (propriedade == "ptxEmitterRule:m_particleLifeKFP" && numero > 0.25m))
                        throw new InvalidDataException("Vida/dimensão da chama fora do limite.");
                    valor.SetAttributeValue(eixo, numero.ToString(CultureInfo.InvariantCulture));
                }
            calibradas.Add((dicionario, id, propriedade));
        }
        var chama = particulas["veh_exhaust_backfire"];
        Calibrar("ParticleRuleDictionary", "veh_exhaust_backfire", chama, "ptxu_Size:m_whdMinKFP", 2m);
        Calibrar("ParticleRuleDictionary", "veh_exhaust_backfire", chama, "ptxu_Size:m_whdMaxKFP", 2m);
        var emissor = emissores["veh_exhaust_backfire"];
        Calibrar("EmitterRuleDictionary", "veh_exhaust_backfire", emissor, "ptxEmitterRule:m_particleLifeKFP", 1.5m);
        Calibrar("EmitterRuleDictionary", "veh_exhaust_backfire", emissor, "ptxEmitterRule:m_speedScalarKFP", 1.25m);
        // WHD ×2 e evento ×10 compensam raiz 1%, aproximando a dimensão original só da chama.
        eventoChama = efeitos[efeito].Element("EventEmitters")!.Elements("Item").Single(n =>
            n.Element("EmitterRule")?.Value == "veh_exhaust_backfire"
            && n.Element("ParticleRule")?.Value == "veh_exhaust_backfire");
        foreach (var campo in new[] { "ZoomScalarMin", "ZoomScalarMax" })
        {
            var valor = eventoChama.Element(campo)!;
            var numero = decimal.Parse(valor.Attribute("value")!.Value, CultureInfo.InvariantCulture) * 10m;
            if (numero <= 0 || numero > 20m) throw new InvalidDataException("Zoom do evento da chama fora do limite.");
            valor.SetAttributeValue("value", numero.ToString(CultureInfo.InvariantCulture));
        }
    }

    var cores = new HashSet<string>(ptUsadas.Where(n => n is "veh_exhaust_backfire" or "veh_backfire_glow" or "veh_nitrous_flames" or "veh_nitrous_glow"));
    if (cores.Count != 2) throw new InvalidDataException("Esperadas regras de chama e glow.");
    var curvas = 0;
    void Neutralizar(XElement propriedade)
    {
        foreach (var valor in propriedade.Descendants("KeyframeValue"))
        {
            // Preserva W (alpha), tempo e intensidade luminosa. Somente RGB é neutralizado.
            valor.SetAttributeValue("x", "1"); valor.SetAttributeValue("y", "1"); valor.SetAttributeValue("z", "1"); curvas++;
        }
    }
    var texturasCinza = new HashSet<string>();
    foreach (var id in cores)
    {
        var regra = particulas[id];
        var cor = regra.Descendants("Item").Single(n => n.Element("Type")?.Attribute("value")?.Value == "Colour");
        cor.Element("RGBCanTint")!.SetAttributeValue("value", "1");
        Neutralizar(cor.Element("RGBAMinKFP")!); Neutralizar(cor.Element("RGBAMaxKFP")!);
        foreach (var shader in regra.Element("ShaderVars")!.Elements("Item"))
            if (shader.Element("Name")?.Value.StartsWith("diffuse", StringComparison.Ordinal) == true
                && !string.IsNullOrEmpty(shader.Element("TextureName")?.Value)) texturasCinza.Add(shader.Element("TextureName")!.Value);
        foreach (var evento in raiz.Element("EffectRuleDictionary")!.Descendants("Item").Where(n => n.Element("ParticleRule")?.Value == id))
            foreach (var prop in evento.Descendants("Item").Where(n => n.Element("Name")?.Value is "ptxu_Colour:m_rgbaMinKFP" or "ptxu_Colour:m_rgbaMaxKFP")) Neutralizar(prop);
    }

    var reserva = LerXml(xmlTexturas).Root!;
    var texLocais = Indice(raiz, "TextureDictionary"); var texReserva = Indice(reserva, "TextureDictionary");
    var origensTex = new Dictionary<string, string>();
    var texDic = new XElement("TextureDictionary");
    foreach (var shader in raiz.Element("ParticleRuleDictionary")!.Descendants("Item").Where(n => n.Element("Type")?.Attribute("value")?.Value == "Texture"))
    {
        var id = shader.Element("TextureName")?.Value ?? "";
        if (id.Length == 0) continue;
        if (!origensTex.ContainsKey(id))
        {
            bool local = texLocais.TryGetValue(id, out var tex);
            if (!local && !texReserva.TryGetValue(id, out tex)) throw new InvalidDataException($"Textura ausente: {id}");
            texDic.Add(new XElement(tex!));
            origensTex[id] = Path.GetDirectoryName(local ? xmlOrigem : xmlTexturas)!;
        }
        shader.Element("ExternalReference")!.SetAttributeValue("value", "0");
    }
    raiz.Element("TextureDictionary")?.Remove(); raiz.Add(texDic);
    Directory.CreateDirectory(destino);
    var pixelsModificados = 0;
    var pixelsEsperados = new Dictionary<string, byte[]>();
    foreach (var tex in texDic.Elements("Item"))
    {
        var id = tex.Element("Name")!.Value; var arquivo = tex.Element("FileName")!.Value;
        if (Path.GetFileName(arquivo) != arquivo) throw new InvalidDataException("Caminho DDS inválido.");
        var bytes = File.ReadAllBytes(Path.Combine(origensTex[id], arquivo));
        if (texturasCinza.Contains(id))
        {
            var t = DDSIO.GetTexture(bytes); var mips = new List<byte>();
            for (int mip = 0; mip < t.Levels; mip++)
            {
                var px = DDSIO.GetPixels(t, mip) ?? throw new InvalidDataException("Formato DDS não suportado.");
                for (int i = 0; i < px.Length; i += 4)
                {
                    var cinza = Math.Max(px[i], Math.Max(px[i + 1], px[i + 2]));
                    if (px[i] != px[i + 1] || px[i] != px[i + 2]) pixelsModificados++;
                    px[i] = px[i + 1] = px[i + 2] = cinza; // alpha intocado
                }
                mips.AddRange(px);
            }
            t.Format = TextureFormat.D3DFMT_A8R8G8B8; t.Stride = checked((ushort)(t.Width * 4));
            t.Data = new TextureData { FullData = mips.ToArray() };
            pixelsEsperados[id] = t.Data.FullData;
            bytes = DDSIO.GetDDSFile(t); tex.Element("Format")!.Value = t.Format.ToString();
        }
        File.WriteAllBytes(Path.Combine(destino, arquivo), bytes);
    }
    var xml = doc.ToString();
    var gerado = XmlYpt.GetYpt(xml, destino);
    var binario = gerado.Save();
    var relido = new YptFile(); relido.Load(binario);
    if (!string.IsNullOrEmpty(relido.ErrorMessage) || relido.PtfxList == null) throw new InvalidDataException("Falha no round-trip YPT.");
    var roundTrip = XDocument.Parse(YptXml.GetXml(relido));
    if (roundTrip.Root!.Element("Name")!.Value != nome
        || Indice(roundTrip.Root, "EffectRuleDictionary").Count != efUsados.Count
        || !Indice(roundTrip.Root, "EffectRuleDictionary").ContainsKey("chama_rgb")) throw new InvalidDataException("Identidade alterada no round-trip.");
    if (!Indice(roundTrip.Root, "ParticleRuleDictionary").Keys.ToHashSet().SetEquals(ptUsadas)
        || !Indice(roundTrip.Root, "EmitterRuleDictionary").Keys.ToHashSet().SetEquals(emUsados)
        || !Indice(roundTrip.Root, "TextureDictionary").Keys.ToHashSet().SetEquals(origensTex.Keys))
        throw new InvalidDataException("Closure de dependências alterada no round-trip.");
    foreach (var id in cores)
    {
        var regra = Indice(roundTrip.Root, "ParticleRuleDictionary")[id];
        var cor = regra.Descendants("Item").Single(n => n.Element("Type")?.Attribute("value")?.Value == "Colour");
        if (cor.Element("RGBCanTint")!.Attribute("value")!.Value != "1") throw new InvalidDataException("Tint perdido no round-trip.");
        foreach (var tipo in new[] { "RGBAMinKFP", "RGBAMaxKFP" })
        {
            var esperados = particulas[id].Descendants(tipo).Single().Descendants("Keyframes").Single().Elements("Item").ToArray();
            var atuais = cor.Element(tipo)!.Descendants("Keyframes").Single().Elements("Item").ToArray();
            if (esperados.Length != atuais.Length) throw new InvalidDataException("Número de keyframes alterado.");
            for (int i = 0; i < esperados.Length; i++)
                foreach (var campo in new[] { "KeyframeTime", "KeyframeValue" })
                    foreach (var eixo in new[] { "x", "y", "z", "w" })
                    {
                        float esperado = float.Parse(esperados[i].Element(campo)!.Attribute(eixo)!.Value, CultureInfo.InvariantCulture);
                        float atual = float.Parse(atuais[i].Element(campo)!.Attribute(eixo)!.Value, CultureInfo.InvariantCulture);
                        if (esperado != atual) throw new InvalidDataException($"Curva/alpha alterado: {id}/{tipo}/{i}/{campo}/{eixo}.");
                    }
        }
    }
    foreach (var tex in relido.PtfxList.TextureDictionary.Textures.data_items)
    {
        if (!pixelsEsperados.TryGetValue(tex.Name, out var esperado)) continue;
        var atual = new List<byte>();
        for (int mip = 0; mip < tex.Levels; mip++) atual.AddRange(DDSIO.GetPixels(tex, mip));
        if (!esperado.AsSpan().SequenceEqual(atual.ToArray())) throw new InvalidDataException($"Pixels/alpha alterados: {tex.Name}.");
    }
    foreach (var (dicionario, id, propriedade) in calibradas)
    {
        var esperado = Indice(raiz, dicionario)[id].Descendants().Single(n => n.Element("Name")?.Value == propriedade);
        var atual = Indice(roundTrip.Root, dicionario)[id].Descendants().Single(n => n.Element("Name")?.Value == propriedade);
        var chavesEsperadas = esperado.Descendants("Keyframes").Single().Elements("Item").ToArray();
        var chavesAtuais = atual.Descendants("Keyframes").Single().Elements("Item").ToArray();
        if (chavesEsperadas.Length != chavesAtuais.Length) throw new InvalidDataException("Curva calibrada perdeu keyframes.");
        for (int i = 0; i < chavesEsperadas.Length; i++)
            foreach (var campo in new[] { "KeyframeTime", "KeyframeValue" })
                foreach (var eixo in new[] { "x", "y", "z", "w" })
                {
                    float a = float.Parse(chavesEsperadas[i].Element(campo)!.Attribute(eixo)!.Value, CultureInfo.InvariantCulture);
                    float b = float.Parse(chavesAtuais[i].Element(campo)!.Attribute(eixo)!.Value, CultureInfo.InvariantCulture);
                    float tolerancia = campo == "KeyframeValue" && eixo is "x" or "y" ? 1e-6f * Math.Max(1, Math.Abs(a)) : 0;
                    if (!float.IsFinite(b) || Math.Abs(a - b) > tolerancia) throw new InvalidDataException($"Calibração alterada: {id}/{propriedade}.");
                }
    }
    if (eventoChama != null)
    {
        var atual = Indice(roundTrip.Root, "EffectRuleDictionary")["chama_rgb"]
            .Element("EventEmitters")!.Elements("Item").Single(n =>
                n.Element("EmitterRule")?.Value == "veh_exhaust_backfire"
                && n.Element("ParticleRule")?.Value == "veh_exhaust_backfire");
        foreach (var campo in new[] { "ZoomScalarMin", "ZoomScalarMax" })
            if (float.Parse(eventoChama.Element(campo)!.Attribute("value")!.Value, CultureInfo.InvariantCulture)
                != float.Parse(atual.Element(campo)!.Attribute("value")!.Value, CultureInfo.InvariantCulture))
                throw new InvalidDataException("Zoom do evento da chama alterado no round-trip.");
    }
    File.WriteAllBytes(Path.Combine(destino, nome + ".ypt"), binario);
    File.WriteAllText(Path.Combine(destino, nome + ".ypt.xml"), xml);
    Console.WriteLine($"{nome}: {efUsados.Count} efeito(s), {emUsados.Count} emissores, {ptUsadas.Count} partículas, {origensTex.Count} texturas; {curvas} keyframes RGB neutros, {pixelsModificados} pixels neutralizados; {calibradas.Count} curvas de chama calibradas; {binario.Length} bytes; SHA256={Convert.ToHexString(SHA256.HashData(binario))}");
}
