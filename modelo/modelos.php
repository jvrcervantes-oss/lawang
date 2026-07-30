<?php
/**
 * Catálogo de modelos de villa — fuente única de las landings /modelo/<id>.
 *
 * 30-jul-2026: **solo Dali**. El foco del funnel es un único modelo hasta que convierta;
 * Dune, Dream, Trinity y Temple se retiraron a propósito (decisión del owner). Volver a
 * publicar uno es añadir su entrada aquí y dejar sus renders en
 * assets/img/buildings/<id>/web/. Nada más.
 *
 * REGLAS DE ESTE FICHERO (no son estilo, son las que evitan publicar mentiras):
 *
 * 1. `precio_desde_eur` a null mientras el owner no cierre NUESTRO precio. La página no
 *    enseña cifra y se marca `noindex` sola. Los precios de bonian.lawangproperties.com
 *    son de OTRO operador: referencia de mercado, no nuestros.
 * 2. `acabados` y `alcance` solo se rellenan con lo verificado en el anexo de obra del
 *    modelo. Extrapolar el pliego de Dali a otro modelo sería inventarse un contrato.
 * 3. Las imágenes NO se listan aquí: se leen de assets/img/buildings/<id>/web/.
 * 4. Un modelo SIN imágenes no es publicable: /modelo/<id> manda a /thecollection en vez
 *    de servir una landing vacía.
 */

return [
    'dali' => [
        'nombre'           => 'Dali',
        'dormitorios'      => 1,
        // Va en el hero, bajo el titular: 20 palabras como techo. Más largo y el titular
        // deja de leerse de un vistazo, que es lo único que hace el tráfico de pago.
        'sub'              => 'Obra nueva llave en mano. Eliges parcela y acabado, y el precio se cierra antes de firmar.',
        'precio_desde_eur' => null,
        // Los tres acabados de cubierta del pliego del contratista (anexo de obra de Dali).
        'acabados'         => [
            ['n' => 'Alang-alang',        'd' => 'Cubierta vegetal tradicional balinesa. La estética más integrada en el entorno tropical.'],
            ['n' => 'Bambú y Sirap Ulin', 'd' => 'Estructura de bambú combinada con teja de madera ulin. Carácter artesanal con mayor durabilidad.'],
            ['n' => 'Sirap Ulin',         'd' => 'Teja de madera ulin, la más resistente al clima húmedo y la de mantenimiento más bajo.'],
        ],
        'alcance'          => [
            'incluido' => [
                'Edificio principal según proyecto',
                'Cubierta del acabado elegido',
                'Piscina overflow en piedra sukabumi',
                'Terraza exterior',
                'Aire acondicionado y agua caliente',
                'Acometida eléctrica PLN 3.500 W',
                'Estructura, arquitectura e instalaciones',
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
];
