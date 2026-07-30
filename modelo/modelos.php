<?php
/**
 * Catálogo de modelos de villa — fuente única de las landings /modelo/<id>.
 *
 * REGLAS DE ESTE FICHERO (no son estilo, son las que evitan publicar mentiras):
 *
 * 1. `precio_desde_eur` a null mientras el owner no cierre NUESTRO precio. La página
 *    enseña "precio pendiente" y se pone `noindex` ella sola. Los precios de
 *    bonian.lawangproperties.com son de OTRO operador: referencia de mercado, no nuestros.
 * 2. `acabados` y `alcance` solo se rellenan con lo verificado en el anexo de obra del
 *    modelo. Dali es el único con anexo leído; extrapolar su pliego a Dune o Dream sería
 *    inventarse un contrato.
 * 3. Las imágenes NO se listan aquí: se leen de assets/img/buildings/<id>/web/. Añadir
 *    renders de un modelo es soltar ficheros en su carpeta, sin tocar código.
 * 4. Un modelo SIN imágenes no es publicable: /modelo/<id> manda a /thecollection en vez
 *    de servir una landing vacía. Hoy le pasa a Dune, Trinity y Temple.
 */

// Los tres acabados de cubierta del pliego del contratista (anexo de obra de Dali).
$ACABADOS_DALI = [
    ['n' => 'Alang-alang',        'd' => 'Cubierta vegetal tradicional balinesa. La estética más integrada en el entorno tropical.'],
    ['n' => 'Bambú + Sirap Ulin', 'd' => 'Estructura de bambú combinada con teja de madera ulin. Carácter artesanal con mayor durabilidad.'],
    ['n' => 'Sirap Ulin',         'd' => 'Teja de madera ulin, la más resistente al clima húmedo y la de mantenimiento más bajo.'],
];

return [
    'dali' => [
        'nombre'           => 'Dali',
        'dormitorios'      => 1,
        'sub'              => 'Villa de obra nueva con piscina overflow en piedra sukabumi, terraza exterior y tres acabados de cubierta a elegir. Se construye sobre la parcela que elijas.',
        'precio_desde_eur' => null,
        'acabados'         => $ACABADOS_DALI,
        'alcance'          => [
            'incluido' => [
                'Edificio principal según proyecto',
                'Cubierta del acabado elegido',
                'Piscina overflow con acabado en piedra sukabumi',
                'Terraza exterior',
                'Aire acondicionado y agua caliente',
                'Acometida eléctrica PLN 3.500 W',
                'Estructura, arquitectura e instalaciones (MEP)',
            ],
            // El pliego solo excluye mobiliario. Si aparecen más partidas fuera de precio
            // (licencias, notaría, IMB/PBG, conexión de agua) van aquí ANTES de publicar:
            // un "no incluido" incompleto es una reclamación.
            'no_incluido' => [
                'Mobiliario interior: camas, armarios, cocina, mesas',
                'Decoración y textiles',
            ],
        ],
    ],

    'dream' => [
        'nombre'           => 'Dream',
        'dormitorios'      => 2,
        'sub'              => 'Villa de obra nueva de dos dormitorios. Se construye sobre la parcela que elijas.',
        'precio_desde_eur' => null,
        'acabados'         => null,   // pendiente: leer su anexo de obra
        'alcance'          => null,   // idem
    ],

    // Sin renders todavía → no publicables. En cuanto haya imágenes en
    // assets/img/buildings/<id>/web/ la landing existe sin tocar nada más.
    'dune' => [
        'nombre'           => 'Dune',
        'dormitorios'      => 1,
        'sub'              => 'Villa de obra nueva de un dormitorio.',
        'precio_desde_eur' => null,
        'acabados'         => null,
        'alcance'          => null,
    ],
    'trinity' => [
        'nombre'           => 'Trinity',
        'dormitorios'      => 3,
        'sub'              => 'Villa de obra nueva de tres dormitorios.',
        'precio_desde_eur' => null,
        'acabados'         => null,
        'alcance'          => null,
    ],
    'temple' => [
        'nombre'           => 'Temple',
        'dormitorios'      => 4,
        'sub'              => 'Villa de obra nueva de cuatro dormitorios.',
        'precio_desde_eur' => null,
        'acabados'         => null,
        'alcance'          => null,
    ],
];
