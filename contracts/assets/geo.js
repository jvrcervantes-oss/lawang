/* ============================================================================
   Nacionalidades y prefijos telefónicos — FUENTE ÚNICA, compartida entre
   Compradores y Contratos (12-ago-2026, petición del owner: "llévalo a
   todos lados donde haya nacionalidad y teléfono en todas las herramientas").
   Vivía solo dentro de compradores/index.html; una lista de ~195 países a
   mano en dos sitios es el mismo problema que ya resolvió entities.js con
   las cuentas bancarias — se corrige en una copia y la otra se queda vieja.
   Sin módulos a propósito: las dos apps son HTML plano con <script> clásico.
   ========================================================================== */
const NACIONALIDADES = ['Afganistán','Albania','Alemania','Andorra','Angola','Antigua y Barbuda',
  'Arabia Saudita','Argelia','Argentina','Armenia','Australia','Austria','Azerbaiyán','Bahamas',
  'Baréin','Bangladés','Barbados','Bélgica','Belice','Benín','Bielorrusia','Birmania (Myanmar)',
  'Bolivia','Bosnia y Herzegovina','Botsuana','Brasil','Brunéi','Bulgaria','Burkina Faso','Burundi',
  'Bután','Cabo Verde','Camboya','Camerún','Canadá','Catar','Chad','Chile','China','Chipre',
  'Ciudad del Vaticano','Colombia','Comoras','Corea del Norte','Corea del Sur','Costa de Marfil',
  'Costa Rica','Croacia','Cuba','Dinamarca','Dominica','Ecuador','Egipto','El Salvador',
  'Emiratos Árabes Unidos','Eritrea','Eslovaquia','Eslovenia','España','Estados Unidos','Estonia',
  'Esuatini','Etiopía','Filipinas','Finlandia','Fiyi','Francia','Gabón','Gambia','Georgia','Ghana',
  'Granada','Grecia','Guatemala','Guinea','Guinea-Bisáu','Guinea Ecuatorial','Guyana','Haití',
  'Honduras','Hungría','India','Indonesia','Irak','Irán','Irlanda','Islandia','Islas Marshall',
  'Islas Salomón','Israel','Italia','Jamaica','Japón','Jordania','Kazajistán','Kenia','Kirguistán',
  'Kiribati','Kuwait','Laos','Lesoto','Letonia','Líbano','Liberia','Libia','Liechtenstein',
  'Lituania','Luxemburgo','Macedonia del Norte','Madagascar','Malasia','Malaui','Maldivas','Malí',
  'Malta','Marruecos','Mauricio','Mauritania','México','Micronesia','Moldavia','Mónaco','Mongolia',
  'Montenegro','Mozambique','Namibia','Nauru','Nepal','Nicaragua','Níger','Nigeria','Noruega',
  'Nueva Zelanda','Omán','Países Bajos','Pakistán','Palaos','Palestina','Panamá',
  'Papúa Nueva Guinea','Paraguay','Perú','Polonia','Portugal','Reino Unido',
  'República Centroafricana','República Checa','República del Congo',
  'República Democrática del Congo','República Dominicana','Ruanda','Rumania','Rusia','Samoa',
  'San Cristóbal y Nieves','San Marino','San Vicente y las Granadinas','Santa Lucía',
  'Santo Tomé y Príncipe','Senegal','Serbia','Seychelles','Sierra Leona','Singapur','Siria',
  'Somalia','Sri Lanka','Sudáfrica','Sudán','Sudán del Sur','Suecia','Suiza','Surinam','Tailandia',
  'Taiwán','Tanzania','Tayikistán','Timor Oriental','Togo','Tonga','Trinidad y Tobago','Túnez',
  'Turkmenistán','Turquía','Tuvalu','Ucrania','Uganda','Uruguay','Uzbekistán','Vanuatu','Venezuela',
  'Vietnam','Yemen','Yibuti','Zambia','Zimbabue'];

/* Prefijo telefónico internacional (E.164) por país — desplegable aparte del
   número para no depender de que cada agente escriba bien el "+34"/"+62"
   (petición del owner, 11-ago-2026). ponytail: los ~12 países que comparten
   +1 (EE. UU./Canadá y el Caribe angloparlante — mismo NANP) y Rusia/Kazajistán
   con +7 van con UNA entrada genérica, no 12 filas idénticas por número — este
   desplegable elige el país, no valida el número completo. */
const PREFIJOS = [['+93','Afganistán'],['+355','Albania'],['+49','Alemania'],['+376','Andorra'],
  ['+244','Angola'],['+966','Arabia Saudita'],['+213','Argelia'],['+54','Argentina'],
  ['+374','Armenia'],['+61','Australia'],['+43','Austria'],['+994','Azerbaiyán'],['+973','Baréin'],
  ['+880','Bangladés'],['+32','Bélgica'],['+501','Belice'],['+229','Benín'],['+375','Bielorrusia'],
  ['+95','Birmania (Myanmar)'],['+591','Bolivia'],['+387','Bosnia y Herzegovina'],
  ['+267','Botsuana'],['+55','Brasil'],['+673','Brunéi'],['+359','Bulgaria'],
  ['+226','Burkina Faso'],['+257','Burundi'],['+975','Bután'],['+238','Cabo Verde'],
  ['+855','Camboya'],['+237','Camerún'],['+974','Catar'],['+235','Chad'],['+56','Chile'],
  ['+86','China'],['+357','Chipre'],['+379','Ciudad del Vaticano'],['+57','Colombia'],
  ['+269','Comoras'],['+850','Corea del Norte'],['+82','Corea del Sur'],['+225','Costa de Marfil'],
  ['+506','Costa Rica'],['+385','Croacia'],['+53','Cuba'],['+45','Dinamarca'],['+593','Ecuador'],
  ['+20','Egipto'],['+503','El Salvador'],['+971','Emiratos Árabes Unidos'],['+291','Eritrea'],
  ['+421','Eslovaquia'],['+386','Eslovenia'],['+34','España'],['+1','Estados Unidos / Canadá / Caribe'],
  ['+372','Estonia'],['+268','Esuatini'],['+251','Etiopía'],['+63','Filipinas'],['+358','Finlandia'],
  ['+679','Fiyi'],['+33','Francia'],['+241','Gabón'],['+220','Gambia'],['+995','Georgia'],
  ['+233','Ghana'],['+30','Grecia'],['+502','Guatemala'],['+224','Guinea'],['+245','Guinea-Bisáu'],
  ['+240','Guinea Ecuatorial'],['+592','Guyana'],['+509','Haití'],['+504','Honduras'],
  ['+36','Hungría'],['+91','India'],['+62','Indonesia'],['+964','Irak'],['+98','Irán'],
  ['+353','Irlanda'],['+354','Islandia'],['+692','Islas Marshall'],['+677','Islas Salomón'],
  ['+972','Israel'],['+39','Italia'],['+81','Japón'],['+962','Jordania'],['+7','Kazajistán / Rusia'],
  ['+254','Kenia'],['+996','Kirguistán'],['+686','Kiribati'],['+965','Kuwait'],['+856','Laos'],
  ['+266','Lesoto'],['+371','Letonia'],['+961','Líbano'],['+231','Liberia'],['+218','Libia'],
  ['+423','Liechtenstein'],['+370','Lituania'],['+352','Luxemburgo'],['+389','Macedonia del Norte'],
  ['+261','Madagascar'],['+60','Malasia'],['+265','Malaui'],['+960','Maldivas'],['+223','Malí'],
  ['+356','Malta'],['+212','Marruecos'],['+230','Mauricio'],['+222','Mauritania'],['+52','México'],
  ['+691','Micronesia'],['+373','Moldavia'],['+377','Mónaco'],['+976','Mongolia'],
  ['+382','Montenegro'],['+258','Mozambique'],['+264','Namibia'],['+674','Nauru'],['+977','Nepal'],
  ['+505','Nicaragua'],['+227','Níger'],['+234','Nigeria'],['+47','Noruega'],['+64','Nueva Zelanda'],
  ['+968','Omán'],['+31','Países Bajos'],['+92','Pakistán'],['+680','Palaos'],['+970','Palestina'],
  ['+507','Panamá'],['+675','Papúa Nueva Guinea'],['+595','Paraguay'],['+51','Perú'],['+48','Polonia'],
  ['+351','Portugal'],['+44','Reino Unido'],['+236','República Centroafricana'],
  ['+420','República Checa'],['+242','República del Congo'],['+243','República Democrática del Congo'],
  ['+250','Ruanda'],['+40','Rumania'],['+685','Samoa'],['+378','San Marino'],
  ['+239','Santo Tomé y Príncipe'],['+221','Senegal'],['+381','Serbia'],['+248','Seychelles'],['+232','Sierra Leona'],['+65','Singapur'],
  ['+963','Siria'],['+252','Somalia'],['+94','Sri Lanka'],['+27','Sudáfrica'],['+249','Sudán'],
  ['+211','Sudán del Sur'],['+46','Suecia'],['+41','Suiza'],['+597','Surinam'],['+66','Tailandia'],
  ['+886','Taiwán'],['+255','Tanzania'],['+992','Tayikistán'],['+670','Timor Oriental'],['+228','Togo'],
  ['+676','Tonga'],['+216','Túnez'],['+993','Turkmenistán'],['+90','Turquía'],['+688','Tuvalu'],
  ['+380','Ucrania'],['+256','Uganda'],['+598','Uruguay'],['+998','Uzbekistán'],['+678','Vanuatu'],
  ['+58','Venezuela'],['+84','Vietnam'],['+967','Yemen'],['+253','Yibuti'],['+260','Zambia'],
  ['+263','Zimbabue']];

/* Separa un teléfono guardado ("+34 612345678") en prefijo+número para
   precargar los dos campos. Prueba los prefijos más largos primero (evita que
   un "+1" de 2 caracteres se coma el principio de un número que en realidad
   empieza por otro prefijo de 3+ dígitos). Si no reconoce ninguno (número
   antiguo sin prefijo, o formato raro) deja el desplegable en blanco y el
   número TAL CUAL en vez de perder el dato. */
function partirTelefono(tel){
  const t = String(tel||'').trim();
  if(!t) return { prefijo:'', numero:'' };
  const p = [...PREFIJOS].sort((a,b)=>b[0].length-a[0].length).find(([cod]) => t.startsWith(cod));
  return p ? { prefijo:p[0], numero:t.slice(p[0].length).trim() } : { prefijo:'', numero:t };
}
