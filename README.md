# hackios-s62

Experimento: arrancar el kernel XNU (generación iOS 16, xnu-8796) en un CAT S62
(Qualcomm SDM660, ARMv8.0, páginas de 4K, eMMC), con vistas a ejecutar userland de iOS.

**Estado: en bring-up del kernel. Nada arranca todavía en el teléfono.**

## Cómo se compila

GitHub Actions (`.github/workflows/xnu.yml`, runner macOS):

1. Descarga [blacktop/darwin-xnu-build](https://github.com/blacktop/darwin-xnu-build) y la serie
   de parches de [dipa-studio/ios-sweet](https://github.com/dipa-studio/ios-sweet) en commits fijados
   (no se copian a este repo).
2. Aplica encima los parches propios de `xnu/patches/` (delta S62: 4K, ARMv8.0, framebuffer).
3. Publica el resultado (resumen del log y kernel comprimido) en la rama `ci-out`.

Ver `NOTES.md` para el estado detallado, hechos de hardware y siguientes pasos.
