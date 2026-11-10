# Notas de trabajo (actualizar tras cada hito)

## Hardware (comprobado en el DTB de stock y con fastboot)
- CAT S62, SDM660 (Kryo 260: núcleos clase Cortex-A73/A53, ARMv8.0, sin LSE/PAN, sin gránulo 16K).
- Almacenamiento eMMC (`fastboot getvar variant` = SDM EMMC), SDHCI sdhc_1 en 0xc0c4000.
- GICv3: GICD 0x17a00000, GICR 0x17b00000. Timer armv8, PPI virtual 3 -> INTID 19. PSCI 1.0.
- Framebuffer de ABL: 0x9d400000, 1080x2160, stride 4320, región de 0x2300000.
- RAM usada por el shim: base 0xb0000000. Táctil probable: Himax I2C 0x48.

## Decisiones
- Descartado parchear el kernelcache binario de Apple (iOS 12, iPhone 6): sin IOKit ni drivers.
- Kernel: xnu-8796 + serie ios-sweet (aplica limpia) + delta S62. Se descartó xnu-4903 porque
  80/81 parches de ios-sweet no aplican ahí; con 8796 se reutiliza todo.
- Config de máquina: se reutiliza `SWEET` (no se renombra para no tocar los 81 parches).

## Delta S62 (xnu/patches/9000-*)
- `-mcpu=cortex-a53+crypto` en vez de armv8.2; sin PAN.
- Páginas 4K: sin `__ARM_16K_PG__`, layout no-LARGE_MEMORY (link 0xfffffff007004000),
  zona/compresor con tamaños "embedded", L2 de low globals, assert de commpage desactivado.
  (Recetas tomadas de inokinoki/xnu-bcm2837-hackintosh, que arranca xnu-8796 4K en QEMU raspi3b.)
- Framebuffer temprano en 0x9d400000 con 5 bloques L2 de 2MB.

## Riesgos abiertos
- Userland iOS 16 (iPhone X) sobre kernel 4K y CPU ARMv8.0: sin verificar. Si no funciona,
  alternativa: userland más antiguo.
- Drivers de ios-sweet con direcciones del SM7150 (UFS, SPMI, RPMh, táctil Goodix, USB):
  hay que desactivarlos o portarlos; falta driver eMMC/SDHCI.
- El script de build omite en silencio parches que no aplican: revisar `patches.txt` en `ci-out`.

- Indicio en contra del userland iOS 16: el propio xnu-8796 usa `casa` (LSE, ARMv8.1) sin
  condición en el commpage, es decir, Apple da LSE por hecho en esa generación. Es probable
  que los binarios de iOS 16 también; haría falta emular LSE en el kernel (trap) o usar un
  userland más antiguo.

## Historial CI
- Run 42924895413 (macos-15, Xcode 16.0): los 81 parches + 9000 aplican; un único error de
  compilación en todo el kernel (`casa` en commpage_asm.s). Corregido con LL/SC.

## Siguiente
1. Que la compilación CI termine (ver rama `ci-out`: RUN.txt, patches.txt, errors.txt).
2. Arrancar el kernel en QEMU (`-cpu cortex-a53`, 4K) antes de probar en el teléfono.
3. ADT S62 + payload + `fastboot boot` (temporal, sin flashear).
