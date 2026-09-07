<?php
/**
 * Catálogo de modelos de villa — la web lo lee de SUPABASE desde el 7-sep-2026.
 *
 * Este fichero era, hasta hoy, un array de 180 líneas escrito a mano con las
 * specs y los precios de los cinco modelos. Se ha quedado en una línea a
 * propósito, y el motivo no es estética:
 *
 *   · Un modelo de villa lo da de alta el cliente. La norma del estudio dice que
 *     un dato así NO puede vivir en un fichero del repo (contexto/suite_lawang.md
 *     → «Si el cliente lo puede dar de alta, no puede vivir en un fichero»), y la
 *     razón está medida: en cuanto lo hace, las dos listas divergen y la del
 *     fichero gana en la pantalla donde esté escrita, sin avisar a nadie.
 *   · Ya había pasado. El 7-sep esta web publicaba Dune a 68.000 € y Dream a
 *     101.000 mientras `modelos_villa` —la tabla que precarga el precio de
 *     construcción de un CONTRATO— seguía en 64.000 y 94.000, sin tocarse desde
 *     el 31-jul. Cuatro y siete mil euros de diferencia entre lo que se publica
 *     y lo que se firma.
 *
 * Ahora la fuente es la tabla `modelos`, que se edita en /intranet/modelos/, y
 * la sirve el RPC `catalogo_publico()` — solo modelos publicados y solo columnas
 * elegidas a mano.
 *
 * LA FORMA DEL ARRAY NO CAMBIA. `index.php`, `lib.php`, `datos.php` y
 * `test_modelo.php` siguen recibiendo exactamente lo mismo que recibían del
 * fichero: mismas claves, mismos tipos. Cambiar de dónde sale un dato no tiene
 * por qué cambiar a quien lo usa, y ese contrato es lo que ha permitido hacer
 * esto sin tocar las 2.600 líneas de la plantilla.
 *
 * La caché, el respaldo para arranque en frío y los porqués de cada nivel están
 * en `catalogo.php`, al lado del código. Las reglas de negocio que antes vivían
 * en la cabecera de este fichero (el corte de precio de 2027 lo decide el reloj
 * del servidor; `renders_pendientes` es la única forma de publicar un modelo sin
 * fotos; los acabados y el alcance solo se rellenan con lo verificado en el
 * anexo de obra de ESE modelo) siguen vigentes: viven ahora en los comentarios
 * de las columnas de la base y en la migración que las creó.
 */
require_once __DIR__ . '/catalogo.php';
return lw_catalogo();
