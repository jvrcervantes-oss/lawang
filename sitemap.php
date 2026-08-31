<?php
/**
 * sitemap.php — genera /sitemap.xml (rewrite interno en .htaccess) desde las fuentes reales:
 * data.json para las propiedades visibles y modelo/modelos.php para las landings de modelo
 * con renders. Antes era un XML estatico con 5 URLs fijas que nunca listaba una sola
 * propiedad — hallazgo de la auditoria SEO del 31-ago-2026.
 */
require __DIR__ . '/modelo/lib.php'; // lw_modelo_imgs()

header('Content-Type: application/xml; charset=UTF-8');

$SITE = 'https://lawangproperties.com';
$urls = [
    ['loc' => $SITE . '/',              'lastmod' => '2026-07-28', 'freq' => 'weekly', 'pri' => '1.0'],
    ['loc' => $SITE . '/thecollection', 'lastmod' => '2026-07-28', 'freq' => 'weekly', 'pri' => '0.9'],
    ['loc' => $SITE . '/legal',         'lastmod' => '2026-07-28', 'freq' => 'yearly', 'pri' => '0.3'],
    ['loc' => $SITE . '/legal-es',      'lastmod' => '2026-08-05', 'freq' => 'yearly', 'pri' => '0.3'],
    ['loc' => $SITE . '/accessibility', 'lastmod' => '2026-07-28', 'freq' => 'yearly', 'pri' => '0.3'],
];

$today = date('Y-m-d');

$json = json_decode((string) file_get_contents(__DIR__ . '/data.json'), true);
$props = (is_array($json) && isset($json['properties'])) ? $json['properties'] : [];
foreach ($props as $p) {
    if (($p['visible'] ?? null) !== true) continue;
    $id = $p['id'] ?? '';
    if ($id === '') continue;
    $urls[] = ['loc' => $SITE . '/property/' . rawurlencode($id), 'lastmod' => $today, 'freq' => 'weekly', 'pri' => '0.7'];
}

$modelosFile = __DIR__ . '/modelo/modelos.php';
if (file_exists($modelosFile)) {
    $MODELOS = require $modelosFile;
    foreach ($MODELOS as $id => $m) {
        if (lw_modelo_imgs($id)) {
            $urls[] = ['loc' => $SITE . '/modelo/' . rawurlencode($id), 'lastmod' => $today, 'freq' => 'weekly', 'pri' => '0.7'];
        }
    }
}

echo '<' . '?xml version="1.0" encoding="UTF-8"?' . ">\n";
?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
<?php foreach ($urls as $u): ?>
  <url>
    <loc><?= lw_e($u['loc']) ?></loc>
    <lastmod><?= lw_e($u['lastmod']) ?></lastmod>
    <changefreq><?= lw_e($u['freq']) ?></changefreq>
    <priority><?= lw_e($u['pri']) ?></priority>
  </url>
<?php endforeach; ?>
</urlset>
