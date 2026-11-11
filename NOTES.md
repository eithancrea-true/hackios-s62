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

- Run 42926264012: compila. QEMU: assert en sweet_early_map_final (alias del FB en un L1 sin tabla).
- Run 42927711389: pánico `write_pte_fast: PTE write is unaligned` en pmap_create_commpages:
  con >1GB el kernel usa páginas VM de 16K sobre 4K de hardware (PAGE_RATIO 4).
- Run 42929118938 (9e40ed4): en QEMU (`-cpu cortex-a53`) arranca completo hasta
  "Waiting on IOMedia Apple_HFS". Timer/IRQ OK, sin instrucciones indefinidas.

## Hallazgo útil
- PAGE_RATIO 4: el userland ve páginas de 16K aunque el hardware sea 4K (como los SoC 4K de
  Apple con más de 1GB). Reduce el riesgo de "iOS 16 sobre 4K"; el de LSE/ARMv8.0 sigue.

## Siguiente
1. Probar en el teléfono: imagen local `s62-shim/xnu8796/s62-boot-xnu8796.img` (fastboot boot,
   temporal). Boot-args: cpus=1 sweetkeys=0 sweettouch=0 sweetusb=0 wdt=-1. PENDIENTE resultado.
2. Driver eMMC (SDHCI sdhc_1 @0xc0c4000) para montar root.
3. Imagen de sistema iOS en userdata (borra Android; confirmar antes) y prueba de userland.
4. Guardar en el repo unas tools propias (ADT/payload/QEMU) en vez de adaptar las de ios-sweet al vuelo.
