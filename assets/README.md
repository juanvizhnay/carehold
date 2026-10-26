# Assets de CareHold

Fuentes de la marca y de la interfaz. Lo que entra a la app se exporta desde aquí con `scripts/export-assets.py`.

| Archivo | Qué es | Dónde se usa |
|---|---|---|
| `logo_corto.png` | Logo corto (símbolo) | `app-icon/AppIcon.png`, ícono del menú de iOS |
| `logo.png` | Logo completo | `Sources/DesignSystem/Resources/wordmark.png`: login, carga y unión al terapeuta |
| `app-icon/AppIcon.png` | Ícono 1024×1024 generado | `iconPath` en `xtool.yml` |
| `design/` | Referencias, ilustraciones y elementos futuros de la interfaz | — |

- **Logos:** PNG con fondo transparente, lo más grandes posible.
- **Ícono:** si `logo_corto.png` ya es un cuadrado opaco, se usa tal cual. Si no, se centra sobre vainilla `#FAF6EE`.
- **Después de cambiar un logo:** `python3 scripts/export-assets.py` y compilar.
