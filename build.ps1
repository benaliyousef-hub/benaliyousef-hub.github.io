# Static site generator. Keep this file ASCII-only (Windows PowerShell 5.1
# reads scripts without BOM as ANSI). All Spanish text lives in config.json,
# data/ and templates/, which are read as UTF-8.
param([string]$SiteUrl = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$dist = Join-Path $root 'docs'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$es = [System.Globalization.CultureInfo]::GetCultureInfo('es-ES')
$inv = [System.Globalization.CultureInfo]::InvariantCulture

function ReadText([string]$p) { return [System.IO.File]::ReadAllText((Join-Path $root $p), $utf8) }
function ReadJsonArray([string]$p) { $o = ConvertFrom-Json (ReadText $p); return ,@($o | ForEach-Object { $_ }) }
function WriteOut([string]$rel, [string]$text) {
  $p = Join-Path $dist $rel
  $d = Split-Path -Parent $p
  if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
  [System.IO.File]::WriteAllText($p, $text, $utf8)
}
function Esc($s) { return ([string]$s).Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;') }
function Fill([string]$tpl, $map) { foreach ($k in @($map.Keys)) { $tpl = $tpl.Replace('{{' + $k + '}}', [string]$map[$k]) }; return $tpl }
function Num($n) { return ([double]$n).ToString('0.####', $inv) }
function N($n, $d) { return ([double]$n).ToString('N' + $d, $es) }
function Eur($n) {
  $v = [double]$n
  if ($v -ge 20) { return (N $v 0) }
  if ($v -gt 0 -and $v -lt 0.0095) { return (N $v 4) }
  if ($v -gt 0 -and $v -lt 0.095) { return (N $v 3) }
  return (N $v 2)
}
function EurR($n) { if ([double]$n -ge 10) { return (N $n 0) } else { return (Eur $n) } }
function Kwh($n) {
  $v = [double]$n
  if ($v -ge 100) { return (N $v 0) }
  if ($v -ge 10) { return (N $v 1) }
  if ($v -gt 0 -and $v -lt 0.1) { return (N $v 3) }
  return (N $v 2)
}
function Cap([string]$s) { return $s.Substring(0, 1).ToUpper($es) + $s.Substring(1) }
function FechaLarga([string]$iso) { return [datetime]::ParseExact($iso, 'yyyy-MM-dd', $inv).ToString("d 'de' MMMM 'de' yyyy", $es) }
function Ld($obj) { return '<script type="application/ld+json">' + ($obj | ConvertTo-Json -Depth 12 -Compress) + '</script>' }

$cfg = ConvertFrom-Json (ReadText 'config.json')
if ($SiteUrl) { $cfg.siteUrl = $SiteUrl }
$site = ([string]$cfg.siteUrl).TrimEnd('/')
$precio = [double]$cfg.precioKwh
$precioTxt = N $precio 2
$anio = (Get-Date).Year
$hoy = (Get-Date).ToString('yyyy-MM-dd')
$ver = (Get-Date).ToString('yyyyMMddHHmm')
$aparatos = ReadJsonArray 'data\aparatos.json'
$guias = ReadJsonArray 'data\guias.json'
$paginas = ReadJsonArray 'data\paginas.json'
$cats = @($cfg.categorias | ForEach-Object { $_ })
$tplBase = ReadText 'templates\base.html'
$tplHome = ReadText 'templates\home.html'
$tplAparato = ReadText 'templates\aparato.html'
$tplCalc = ReadText 'templates\calc.html'
$tplLista = ReadText 'templates\lista.html'
$tplTexto = ReadText 'templates\texto.html'
$sitemap = New-Object System.Collections.ArrayList

function Pend($v) { if ([string]::IsNullOrWhiteSpace([string]$v)) { return '[pendiente de completar]' } else { return (Esc $v) } }
$Globales = @{
  nombre_sitio = (Esc $cfg.nombre); lema = (Esc $cfg.lema); precio = $precioTxt; anio = $anio; ver = $ver; site = $site
  titular = (Pend $cfg.titular); nif = (Pend $cfg.nif); domicilio = (Pend $cfg.domicilio); email = (Pend $cfg.email)
  total = $aparatos.Count
}

function T([string]$key, $map) {
  $s = [string]$cfg.textos.$key
  foreach ($k in @($map.Keys)) { $s = $s.Replace('{' + $k + '}', [string]$map[$k]) }
  return $s
}
function Tiempo($h) {
  $v = [double]$h
  if ($v -lt 1) { return ([string][math]::Round($v * 60)) + ' minutos' }
  if ($v -eq 1) { return '1 hora' }
  if ($v -eq [math]::Floor($v)) { return (N $v 0) + ' horas' }
  return (N $v 1) + ' horas'
}
function Calc($a, [string]$lvl) {
  $dias = [double]$a.dias
  if ($a.modo -eq 'ciclo') {
    $k = [double]$a."kwh$lvl"
    $kd = $k * [double]$a.usos / 7
    $unit = $k * $precio
    $pot = (Kwh $k) + ' kWh'
  } else {
    $w = [double]$a."w$lvl"
    $kd = $w * [double]$a.factor * [double]$a.horas / 1000
    $unit = $w * [double]$a.factor / 1000 * $precio
    $pot = (N $w 0) + ' W'
  }
  return [pscustomobject]@{ pot = $pot; kwhDia = $kd; unit = $unit; eurDia = $kd * $precio; eurMes = $kd * 30 * $precio; eurAno = $kd * $dias * $precio; kwhAno = $kd * $dias }
}
function CatOf($a) { return ($cats | Where-Object { $_.slug -eq $a.cat } | Select-Object -First 1) }
function Card($a) {
  $c = Calc $a 'Typ'
  return '<a class="card" href="/cuanto-gasta/' + $a.slug + '/" data-name="' + (Esc $a.nombre) + '"><span class="card-t">' + (Esc (Cap $a.nombre)) + '</span><span class="card-n">&asymp; ' + (Eur $c.eurAno) + ' &euro;/a&ntilde;o</span><span class="card-s">' + $c.pot + ' &middot; ' + (Kwh $c.kwhAno) + ' kWh/a&ntilde;o</span></a>'
}
function RowsTabla($list) {
  $sb = New-Object System.Text.StringBuilder
  foreach ($a in $list) {
    $c = Calc $a 'Typ'
    [void]$sb.Append('<tr><th scope="row"><a href="/cuanto-gasta/' + $a.slug + '/">' + (Esc (Cap $a.nombre)) + '</a></th><td>' + $c.pot + '</td><td>' + (Kwh $c.kwhAno) + ' kWh</td><td>' + (Eur $c.eurMes) + ' &euro;</td><td><strong>' + (Eur $c.eurAno) + ' &euro;</strong></td></tr>')
  }
  return $sb.ToString()
}
function TablaAparatos($list) {
  return '<div class="table-wrap"><table><thead><tr><th scope="col">Aparato</th><th scope="col">Consumo habitual</th><th scope="col">kWh al a&ntilde;o</th><th scope="col">Al mes de uso</th><th scope="col">Al a&ntilde;o</th></tr></thead><tbody>' + (RowsTabla $list) + '</tbody></table></div>'
}
function CalcHtml($a, [string]$selector) {
  $c = Calc $a 'Typ'
  $isC = ($a.modo -eq 'ciclo')
  $m = @{
    modo = $a.modo; selector = $selector; precioNum = (Num $precio); dias = (Num $a.dias)
    w = $(if ($isC) { '1000' } else { Num $a.wTyp }); horas = $(if ($isC) { '1' } else { Num $a.horas })
    factorPct = $(if ($isC) { '100' } else { Num ([double]$a.factor * 100) })
    kwh = $(if ($isC) { Num $a.kwhTyp } else { '1' }); usos = $(if ($isC) { Num $a.usos } else { '3' })
    unitLabel = $(if ($isC) { 'Por uso' } else { 'Por hora' })
    oUnit = (Eur $c.unit) + ' &euro;'; oDia = (Eur $c.eurDia) + ' &euro;'; oMes = (Eur $c.eurMes) + ' &euro;'; oAno = (Eur $c.eurAno) + ' &euro;'
    oKwhDia = (Kwh $c.kwhDia) + ' kWh'; oKwhMes = (Kwh ($c.kwhDia * 30)) + ' kWh'; oKwhAno = (Kwh $c.kwhAno) + ' kWh'
  }
  return (Fill $tplCalc $m)
}
function Crumbs($items) {
  $html = '<nav class="crumbs wrap" aria-label="Migas de pan"><ol>'
  $ld = @(); $i = 0
  foreach ($it in $items) {
    $i++
    if ($it.u) { $html += '<li><a href="' + $it.u + '">' + (Esc $it.n) + '</a></li>'; $ld += [ordered]@{ '@type' = 'ListItem'; position = $i; name = $it.n; item = $site + $it.u } }
    else { $html += '<li aria-current="page">' + (Esc $it.n) + '</li>'; $ld += [ordered]@{ '@type' = 'ListItem'; position = $i; name = $it.n } }
  }
  $html += '</ol></nav>'
  return @{ html = $html; ld = (Ld ([ordered]@{ '@context' = 'https://schema.org'; '@type' = 'BreadcrumbList'; itemListElement = @($ld) })) }
}
function FaqHtml($faq) {
  $s = ''
  foreach ($f in $faq) { $s += '<div class="faq"><h3>' + (Esc $f.q) + '</h3><p>' + (Esc $f.a) + '</p></div>' }
  return $s
}
function FaqLd($faq) {
  $items = @(foreach ($f in $faq) { [ordered]@{ '@type' = 'Question'; name = $f.q; acceptedAnswer = [ordered]@{ '@type' = 'Answer'; text = $f.a } } })
  return (Ld ([ordered]@{ '@context' = 'https://schema.org'; '@type' = 'FAQPage'; mainEntity = $items }))
}
function ArticleLd([string]$headline, [string]$desc, [string]$url, [string]$fecha) {
  return (Ld ([ordered]@{ '@context' = 'https://schema.org'; '@type' = 'Article'; headline = $headline; description = $desc; inLanguage = 'es'; datePublished = $fecha; dateModified = $fecha; mainEntityOfPage = $url; author = [ordered]@{ '@type' = 'Organization'; name = $cfg.nombre; url = $site + '/' }; publisher = [ordered]@{ '@type' = 'Organization'; name = $cfg.nombre; url = $site + '/' } }))
}
function Render($o) {
  $path = '/' + (($o.rel -replace '\\', '/') -replace 'index\.html$', '')
  $title = [string]$o.title
  if (-not $o.rawTitle) { $title = $title + ' | ' + $cfg.nombre }
  $robots = 'index,follow,max-image-preview:large'
  if ($o.noindex) { $robots = 'noindex,follow' }
  $ogType = 'article'; if ($o.ogType) { $ogType = $o.ogType }
  $html = Fill $tplBase @{ title = (Esc $title); desc = (Esc $o.desc); canonical = $site + $path; robots = $robots; ogType = $ogType; jsonld = [string]$o.jsonld; content = [string]$o.content }
  $html = Fill $html $Globales
  WriteOut $o.rel $html
  if (-not $o.noindex) { $lm = $hoy; if ($o.lastmod) { $lm = $o.lastmod }; [void]$sitemap.Add(@{ loc = $site + $path; lastmod = $lm }) }
}

# ---------- clean ----------
if (Test-Path $dist) { Remove-Item -Recurse -Force $dist }
New-Item -ItemType Directory -Force -Path $dist | Out-Null

# ---------- appliance pages ----------
foreach ($a in $aparatos) {
  $cat = CatOf $a
  if (-not $cat) { throw "Categoria desconocida en $($a.slug): $($a.cat)" }
  $lo = Calc $a 'Min'; $ty = Calc $a 'Typ'; $hi = Calc $a 'Max'
  $isC = ($a.modo -eq 'ciclo')
  $base = @{ art = $a.art; ArtCap = (Cap $a.art); nombre = $a.nombre; anio = $anio; precio = $precioTxt; dias = (N $a.dias 0)
    kwhDia = (Kwh $ty.kwhDia); eurDia = (Eur $ty.eurDia); eurMes = (Eur $ty.eurMes); eurAno = (Eur $ty.eurAno)
    eurAnoMin = (EurR $lo.eurAno); eurAnoMax = (EurR $hi.eurAno) }
  if ($isC) {
    $base.kwh = (Kwh $a.kwhTyp); $base.usos = (Num $a.usos).Replace('.', ','); $base.eurUso = (Eur $ty.unit)
    $respuesta = T 'respuestaCiclo' $base; $formula = T 'formulaCiclo' $base; $cargaNota = [string]$cfg.textos.cargaNotaCiclo
    $colPot = 'Consumo por uso'; $unidad = 'uso'
  } else {
    $base.w = (N $a.wTyp 0); $base.tiempo = (Tiempo $a.horas); $base.horasNum = (Num $a.horas).Replace('.', ','); $base.factorPct = (N ([double]$a.factor * 100) 0)
    $respuesta = T 'respuestaPotencia' $base; $formula = T 'formulaPotencia' $base
    $cargaNota = $(if ([double]$a.factor -lt 1) { [string]$cfg.textos.cargaNotaParcial } else { [string]$cfg.textos.cargaNotaTotal })
    $colPot = 'Potencia'; $unidad = 'hora'
  }
  $nota = ''
  if ([double]$a.dias -lt 365) { $nota = T 'notaDias' $base }
  $tabla = ''
  foreach ($r in @(@{ n = 'Bajo'; c = $lo }, @{ n = 'Habitual'; c = $ty }, @{ n = 'Alto'; c = $hi })) {
    $tabla += '<tr><th scope="row">' + $r.n + '</th><td>' + $r.c.pot + '</td><td>' + (Kwh $r.c.kwhDia) + ' kWh</td><td>' + (Eur $r.c.unit) + ' &euro;</td><td>' + (Eur $r.c.eurMes) + ' &euro;</td><td><strong>' + (Eur $r.c.eurAno) + ' &euro;</strong></td></tr>'
  }
  $factores = ''; foreach ($x in $a.factores) { $factores += '<li>' + (Esc $x) + '</li>' }
  $consejos = ''; foreach ($x in $a.consejos) { $consejos += '<li>' + (Esc $x) + '</li>' }
  $amazon = ''
  if (-not [string]::IsNullOrWhiteSpace([string]$cfg.amazonTag)) {
    $u1 = 'https://www.amazon.es/s?k=' + [uri]::EscapeDataString([string]$a.compra) + '&amp;tag=' + $cfg.amazonTag
    $u2 = 'https://www.amazon.es/s?k=' + [uri]::EscapeDataString([string]$cfg.textos.amazonMedidorBusqueda) + '&amp;tag=' + $cfg.amazonTag
    $amazon = '<aside class="shop"><h2>' + $cfg.textos.amazonTitulo + '</h2><p>' + $cfg.textos.amazonTexto + '</p><p class="shop-links"><a rel="sponsored nofollow noopener" target="_blank" href="' + $u2 + '">' + $cfg.textos.amazonMedidor + '</a><a rel="sponsored nofollow noopener" target="_blank" href="' + $u1 + '">' + (T 'amazonAparato' $base) + '</a></p><p class="note">' + $cfg.textos.amazonAviso + '</p></aside>'
  }
  $rel = ''
  foreach ($o in @($aparatos | Where-Object { $_.cat -eq $a.cat -and $_.slug -ne $a.slug } | Select-Object -First 6)) { $rel += (Card $o) }
  $cr = Crumbs @(@{ n = 'Inicio'; u = '/' }, @{ n = 'Aparatos'; u = '/cuanto-gasta/' }, @{ n = $cat.nombre; u = '/categoria/' + $cat.slug + '/' }, @{ n = (Cap $a.nombre) })
  $h1 = T 'h1Aparato' $base
  $title = T 'tituloAparato' $base
  $desc = T 'descAparato' $base
  $url = $site + '/cuanto-gasta/' + $a.slug + '/'
  $content = Fill $tplAparato @{
    bread = $cr.html; catSlug = $cat.slug; catNombre = (Esc $cat.nombre); h1 = (Esc $h1); respuesta = $respuesta
    fechaIso = $a.fecha; fecha = (FechaLarga $a.fecha); calc = (CalcHtml $a ''); nombreCap = (Esc (Cap $a.nombre)); nombre = (Esc $a.nombre)
    colPot = $colPot; unidad = $unidad; tabla = $tabla; nota = $nota; intro = (Esc $a.intro); factores = $factores
    formula = $formula; cargaNota = $cargaNota; consejos = $consejos; amazon = $amazon; faq = (FaqHtml $a.faq); relacionados = $rel
  }
  Render @{ rel = "cuanto-gasta\$($a.slug)\index.html"; title = $title; rawTitle = $true; desc = $desc; content = $content; lastmod = $a.fecha
    jsonld = ($cr.ld + (ArticleLd $h1 $desc $url $a.fecha) + (FaqLd $a.faq)) }
}

# ---------- home ----------
$orden = @($aparatos | Sort-Object { (Calc $_ 'Typ').eurAno } -Descending)
$ranking = ''; $pos = 0
foreach ($a in @($orden | Select-Object -First 10)) {
  $pos++; $c = Calc $a 'Typ'
  $ranking += '<tr><td class="pos">' + $pos + '</td><th scope="row"><a href="/cuanto-gasta/' + $a.slug + '/">' + (Esc (Cap $a.nombre)) + '</a></th><td>' + (Kwh $c.kwhAno) + ' kWh</td><td><strong>' + (Eur $c.eurAno) + ' &euro;</strong></td></tr>'
}
$catTiles = ''
foreach ($cat in $cats) {
  $n = @($aparatos | Where-Object { $_.cat -eq $cat.slug }).Count
  $catTiles += '<a class="tile" href="/categoria/' + $cat.slug + '/"><span class="tile-t">' + (Esc $cat.nombre) + '</span><span class="tile-s">' + (Esc $cat.desc) + '</span><span class="tile-n">' + $n + ' aparatos &rarr;</span></a>'
}
$guiaCards = ''
foreach ($g in $guias) { $guiaCards += '<a class="tile" href="/guias/' + $g.slug + '/"><span class="tile-t">' + (Esc $g.titulo) + '</span><span class="tile-s">' + (Esc $g.desc) + '</span><span class="tile-n">Leer la gu&iacute;a &rarr;</span></a>' }
$alfab = @($aparatos | Sort-Object nombre)
$appData = @(foreach ($a in $alfab) {
  if ($a.modo -eq 'ciclo') { [ordered]@{ s = $a.slug; n = (Cap $a.nombre); m = 'ciclo'; kwh = [double]$a.kwhTyp; usos = [double]$a.usos; dias = [double]$a.dias } }
  else { [ordered]@{ s = $a.slug; n = (Cap $a.nombre); m = 'potencia'; w = [double]$a.wTyp; horas = [double]$a.horas; factor = [double]$a.factor * 100; dias = [double]$a.dias } }
})
$first = $orden[0]
$selector = '<label class="calc-select">Aparato<select id="aparato-select" data-initial="' + $first.slug + '"></select></label><script type="application/json" id="aparatos-data">' + ($appData | ConvertTo-Json -Depth 4 -Compress) + '</script>'
$homeFaq = @($cfg.homeFaq | ForEach-Object { $_ })
$homeContent = Fill $tplHome @{ calc = (CalcHtml $first $selector); ranking = $ranking; categorias = $catTiles; guias = $guiaCards; faq = (FaqHtml $homeFaq) }
$webLd = Ld ([ordered]@{ '@context' = 'https://schema.org'; '@type' = 'WebSite'; name = $cfg.nombre; url = $site + '/'; inLanguage = 'es'; description = $cfg.lema })
Render @{ rel = 'index.html'; title = (T 'tituloHome' @{ anio = $anio }); rawTitle = $true; desc = (T 'descHome' @{ total = $aparatos.Count }); content = $homeContent; ogType = 'website'; jsonld = ($webLd + (FaqLd $homeFaq)) }

# ---------- hub: all appliances ----------
$body = '<p class="filter"><label for="filtro">Busca un aparato</label><input id="filtro" type="search" placeholder="lavadora, router, horno..." autocomplete="off"></p>'
foreach ($cat in $cats) {
  $items = @($aparatos | Where-Object { $_.cat -eq $cat.slug })
  $cards = ''; foreach ($a in $items) { $cards += (Card $a) }
  $body += '<section class="cat-block"><h2><a href="/categoria/' + $cat.slug + '/">' + (Esc $cat.nombre) + '</a></h2><div class="cards">' + $cards + '</div></section>'
}
$body += '<section><h2>' + $cfg.textos.hubTablaTitulo + '</h2>' + (TablaAparatos $alfab) + '<p class="note">' + $cfg.textos.notaTabla + '</p></section>'
$cr = Crumbs @(@{ n = 'Inicio'; u = '/' }, @{ n = 'Aparatos' })
Render @{ rel = 'cuanto-gasta\index.html'; title = (T 'tituloHub' @{ anio = $anio }); desc = (T 'descHub' @{ total = $aparatos.Count }); jsonld = $cr.ld
  content = (Fill $tplLista @{ bread = $cr.html; h1 = $cfg.textos.h1Hub; intro = (T 'introHub' @{ total = $aparatos.Count }); body = $body }) }

# ---------- categories ----------
foreach ($cat in $cats) {
  $items = @($aparatos | Where-Object { $_.cat -eq $cat.slug } | Sort-Object { (Calc $_ 'Typ').eurAno } -Descending)
  $cards = ''; foreach ($a in $items) { $cards += (Card $a) }
  $body = '<div class="cards">' + $cards + '</div><section><h2>' + $cfg.textos.catTablaTitulo + '</h2>' + (TablaAparatos $items) + '<p class="note">' + $cfg.textos.notaTabla + '</p></section>'
  $cr = Crumbs @(@{ n = 'Inicio'; u = '/' }, @{ n = 'Aparatos'; u = '/cuanto-gasta/' }, @{ n = $cat.nombre })
  $lm = ($items | ForEach-Object { $_.fecha } | Sort-Object | Select-Object -Last 1)
  Render @{ rel = "categoria\$($cat.slug)\index.html"; title = (T 'tituloCat' @{ cat = $cat.nombre; anio = $anio }); desc = $cat.meta; jsonld = $cr.ld; lastmod = $lm
    content = (Fill $tplLista @{ bread = $cr.html; h1 = (Esc (T 'h1Cat' @{ cat = $cat.nombre })); intro = (Esc $cat.intro); body = $body }) }
}

# ---------- guides ----------
$gl = ''
foreach ($g in $guias) {
  $gl += '<a class="tile" href="/guias/' + $g.slug + '/"><span class="tile-t">' + (Esc $g.titulo) + '</span><span class="tile-s">' + (Esc $g.desc) + '</span><span class="tile-n">Leer la gu&iacute;a &rarr;</span></a>'
  $cr = Crumbs @(@{ n = 'Inicio'; u = '/' }, @{ n = $cfg.textos.crumbGuias; u = '/guias/' }, @{ n = $g.titulo })
  $url = $site + '/guias/' + $g.slug + '/'
  $bodyG = ReadText ("data\guias\" + $g.slug + '.html')
  Render @{ rel = "guias\$($g.slug)\index.html"; title = $g.titulo; desc = $g.desc; lastmod = $g.fecha; jsonld = ($cr.ld + (ArticleLd $g.titulo $g.desc $url $g.fecha))
    content = (Fill $tplTexto @{ bread = $cr.html; h1 = (Esc $g.titulo); meta = ('Actualizado el <time datetime="' + $g.fecha + '">' + (FechaLarga $g.fecha) + '</time>'); body = $bodyG }) }
}
$cr = Crumbs @(@{ n = 'Inicio'; u = '/' }, @{ n = $cfg.textos.crumbGuias })
Render @{ rel = 'guias\index.html'; title = $cfg.textos.tituloGuias; desc = $cfg.textos.descGuias; jsonld = $cr.ld
  content = (Fill $tplLista @{ bread = $cr.html; h1 = $cfg.textos.h1Guias; intro = $cfg.textos.introGuias; body = ('<div class="tiles">' + $gl + '</div>') }) }

# ---------- static pages ----------
foreach ($p in $paginas) {
  $cr = Crumbs @(@{ n = 'Inicio'; u = '/' }, @{ n = $p.titulo })
  $bodyP = ReadText ("data\paginas\" + $p.slug + '.html')
  Render @{ rel = "$($p.slug)\index.html"; title = $p.titulo; desc = $p.desc; lastmod = $p.fecha; jsonld = $cr.ld; noindex = [bool]$p.noindex
    content = (Fill $tplTexto @{ bread = $cr.html; h1 = (Esc $p.titulo); meta = ('Actualizado el <time datetime="' + $p.fecha + '">' + (FechaLarga $p.fecha) + '</time>'); body = $bodyP }) }
}
Render @{ rel = '404.html'; title = $cfg.textos.titulo404; desc = $cfg.textos.titulo404; noindex = $true
  content = (Fill $tplLista @{ bread = ''; h1 = $cfg.textos.titulo404; intro = $cfg.textos.texto404; body = '<p><a class="btn" href="/cuanto-gasta/">Ver todos los aparatos</a></p>' }) }

# ---------- sitemap, robots, assets ----------
$sm = '<?xml version="1.0" encoding="UTF-8"?>' + "`n" + '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' + "`n"
foreach ($u in $sitemap) { $sm += '  <url><loc>' + $u.loc + '</loc><lastmod>' + $u.lastmod + '</lastmod></url>' + "`n" }
$sm += '</urlset>' + "`n"
WriteOut 'sitemap.xml' $sm
WriteOut 'robots.txt' ("User-agent: *`nAllow: /`n`nSitemap: $site/sitemap.xml`n")
WriteOut '.nojekyll' ''
Copy-Item -Recurse -Force (Join-Path $root 'assets') (Join-Path $dist 'assets')
Copy-Item -Force (Join-Path $root 'assets\favicon.svg') (Join-Path $dist 'favicon.svg')

Write-Output ("OK: " + $sitemap.Count + " paginas indexables, " + $aparatos.Count + " aparatos, " + $guias.Count + " guias -> docs")
if ($site -like '*.example*') { Write-Output 'AVISO: siteUrl es un marcador. Ejecuta con -SiteUrl https://tu-dominio o cambia config.json antes de publicar.' }
foreach ($k in 'titular', 'nif', 'domicilio', 'email') { if ([string]::IsNullOrWhiteSpace([string]$cfg.$k)) { Write-Output "AVISO: falta '$k' en config.json (aviso legal incompleto)." } }
if ([string]::IsNullOrWhiteSpace([string]$cfg.amazonTag)) { Write-Output 'AVISO: amazonTag vacio; los bloques de afiliado no se muestran.' }
