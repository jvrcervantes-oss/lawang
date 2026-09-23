/**
 * Config de BUILD, solo para generar v2.min.css — no es infraestructura de producción
 * (no hay tailwind.config real en el repo, por eso el resto del sitio va con builds
 * congelados o Play CDN). Fusiona dos orígenes verificados contra CSS ya compilado,
 * nunca inventados:
 *   - Los tokens que ya traía investor-deck/palmfield/index.html (su <script> inline,
 *     líneas 93-132: territorial-green, deep-lagoon, soft-canopy, volcanic-ash, etc.)
 *   - "primary" y el resto de tokens nuevos que modelo/index.php usa hoy (extraídos de
 *     assets/dali-tesla-tw.min.css con grep, no adivinados).
 * Regenerar: cd v2 && npx tailwindcss@3 -c tailwind.build.config.js -i input.css -o v2.min.css --minify
 */
module.exports = {
  content: ["./index.html"],
  theme: {
    extend: {
      colors: {
        "territorial-green": "#485B37",
        "deep-lagoon": "#104C4F",
        "burnt-earth": "#42210B",
        "soft-canopy": "#8F9B7A",
        "volcanic-ash": "#2E3437",
        "stone-sand": "#BEB3A5",
        "raw-linen": "#F5F0E6",
        "surface": "#fbf9f4",
        "surface-alt": "#F1EBDD",
        "surface-container-low": "#f5f4ee",
        "surface-container": "#efeee8",
        "surface-container-highest": "#e4e2dd",
        "surface-container-lowest": "#ffffff",
        "primary": "#314322",
        "on-surface": "#1b1c19",
        "on-surface-variant": "#44483f",
        "control-border": "#8A8474",
        "secondary-fixed": "#dbe5cb",
        "tertiary-fixed": "#c8e8d6",
        "on-secondary": "#182008"
      },
      borderRadius: { "DEFAULT": "0.25rem", "lg": "0.5rem", "xl": "0.75rem", "2xl": "1rem", "3xl": "1.5rem", "full": "9999px" },
      spacing: { "margin-mobile": "16px", "element-gap": "16px", "gutter": "24px", "margin-desktop": "48px" },
      fontFamily: {
        "label-md": ["Jost", "sans-serif"], "kpi-number": ["Instrument Sans", "sans-serif"],
        "body-sm": ["Jost", "sans-serif"], "headline-md": ["Cormorant Garamond", "serif"],
        "body-md": ["Jost", "sans-serif"], "body-lg": ["Jost", "sans-serif"],
        "headline-lg": ["Cormorant Garamond", "serif"], "headline-sm": ["Cormorant Garamond", "serif"]
      },
      fontSize: {
        "label-md": ["14px", { lineHeight: "20px", fontWeight: "600" }],
        "kpi-number": ["36px", { lineHeight: "40px", fontWeight: "600" }],
        "body-sm": ["13px", { lineHeight: "20px", fontWeight: "500" }],
        "body-md": ["15px", { lineHeight: "24px", fontWeight: "500" }],
        "body-lg": ["18px", { lineHeight: "28px", fontWeight: "500" }],
        "headline-lg": ["40px", { lineHeight: "48px", fontWeight: "600" }],
        "headline-sm": ["24px", { lineHeight: "32px", fontWeight: "600" }],
        "headline-md": ["28px", { lineHeight: "36px", fontWeight: "600" }]
      }
    }
  }
};
