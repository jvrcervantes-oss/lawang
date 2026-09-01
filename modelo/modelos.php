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
        'sub'              => 'Villa de 1 dormitorio en suite, construida sobre la parcela que elijas. Acabado y presupuesto cerrados por escrito antes de firmar.',
        // 1-sep: landing bilingüe (ES/EN) — mismo dato, traducción profesional de la misma
        // fuente. Nunca se redacta el inglés aparte "a ojo": si el ES cambia, este texto
        // queda desincronizado hasta que alguien lo note.
        'sub_en'           => 'A 1-bedroom en-suite villa, built on the plot you choose. Finish and budget locked in writing before you sign.',
        // 1-sep: precio cerrado dado directamente por el owner en la sesión de trabajo
        // (chat CEO, tras confirmar explícitamente que era la cifra real y no de relleno,
        // en respuesta a la pregunta "¿me das el precio real?"). Quita el `noindex`
        // automático de la landing — ver lw_precio_fmt() en lib.php.
        'precio_desde_eur' => 69000,
        // Los tres acabados de cubierta del pliego del contratista (anexo de obra de Dali).
        'acabados'         => [
            ['n' => 'Alang-alang',        'd' => 'Cubierta vegetal tradicional balinesa. La estética más integrada en el entorno tropical.',
             'n_en' => 'Alang-alang',        'd_en' => 'Traditional Balinese thatch roofing. The look most integrated into the tropical setting.'],
            ['n' => 'Bambú y Sirap Ulin', 'd' => 'Estructura de bambú combinada con teja de madera ulin. Carácter artesanal con mayor durabilidad.',
             'n_en' => 'Bamboo & Ulin shingle', 'd_en' => 'Bamboo structure combined with ulin wood shingle. Handcrafted character and greater durability.'],
            ['n' => 'Sirap Ulin',         'd' => 'Teja de madera ulin, la más resistente al clima húmedo y la de mantenimiento más bajo.',
             'n_en' => 'Ulin shingle',         'd_en' => 'Ulin wood shingle across the whole roof. The most weather-resistant, lowest-maintenance option.'],
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
            'incluido_en' => [
                'Main building per the project design',
                'Roof in the finish you choose',
                'Overflow pool in sukabumi stone',
                'Exterior terrace',
                'Air conditioning and hot water',
                'PLN 3,500W electrical connection',
                'Structure, architecture and installations',
            ],
            // El pliego solo excluye mobiliario. Si aparecen más partidas fuera de precio
            // (licencias, notaría, IMB/PBG, conexión de agua) van aquí ANTES de publicar:
            // un "no incluido" incompleto es una reclamación.
            'no_incluido' => [
                'Mobiliario interior: camas, armarios, cocina, mesas',
                'Decoración y textiles',
            ],
            'no_incluido_en' => [
                'Interior furniture: beds, wardrobes, kitchen, tables',
                'Decor and textiles',
            ],
        ],
    ],
];
