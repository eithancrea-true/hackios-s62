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

## Prueba en hardware
- 2026-11-10, kernel 9e40ed4 en el S62 real (fastboot boot): llega a IOKit, framebuffer y
  `SWEET CPU: cpu=0 entered initCPU`, y se congela ahí (sin pánico). Nunca llega
  `came alive; SGI1 OK`: la auto-IPI (SGI1) y/o el timer no generan interrupción. Sospecha:
  GIC del SDM660 (grupos/seguridad, GICR, ICC_*). Como el bucle usaba IOSleep, sin timer
  se cuelga en silencio.
- 7b602ec: sondeo sin IOSleep para la CPU 0 y volcado `S62 GIC:`/`S62 TMR:` tras 5 s
  (espera 60 s antes del pánico). En QEMU imprime valores de referencia al funcionar.

- 88b1da2 (2026-11-10 20:37): **HITO en hardware.** Tras 5 s sin SGI1, `sweet_gic_retry()`
  reescribe IGROUPR0/IPRIORITYR0/ISENABLER0 del GICR de la CPU 0; ahora SÍ se quedan
  (IPRIORITYR0=a0a0a0a0) y SGI1 llega: "SWEET CPU: 1/1 CPUs initialized, SGI1 verified".
  El kernel sigue (MAC, AMFI, sandbox, HFS, red, Skywalk) hasta
  "Waiting on IOMedia Apple_HFS", igual que en QEMU. Timer e interrupciones funcionan.
  Conclusión: la primera escritura en pe_init_fiq se pierde (TODO: entender por qué; ver
  línea `S62 EARLY` y hacer la reescritura en el sitio correcto en vez de tras 5 s).
  GIC: ARM GIC-500 (IIDR 0x1143b), 5 bits de prioridad, SecurityExtn=1.

- dd1685f + flash en boot_b (2026-11-10 20:59): driver eMMC en hardware. SDCC1 vivo:
  GCC apps 0x4221/ahb 0x20008001 (encendidos), SDHCI v3.0 (ver 0x6b02), pstate 0x01f800f0,
  bus 8 bits, ADMA2-64 seleccionado, HS200 (hctl2 UHS=3), reloj de tarjeta activo.
  Leer 0xc0c8000 REINICIA el teléfono: es el ICE (sdcc1ice@c0c8000, reloj apagado). Los
  registros CQE están en 0xc0c5000 (reg-names: hc_mem, cqhci_mem, cqhci_ice). ADT corregido.
- Flujo de prueba actual: el usuario usa el slot B para pruebas (A = Android stock). Se flashea
  `boot_b` con s62_flash_b.bat (fastboot flash boot_b + set-active b + reboot).
  userdata es compartido entre slots: para la raíz de iOS usar particiones del slot B.

- c859e65 (2026-11-10 21:26): **LECTURA eMMC FUNCIONA** (ADMA2-64, 12 B/descriptor).
  PIO no sirve en este host (buffer-read-enable atascado, puerto de datos da ceros).
  LBA0 55aa tipo ee, GPT 69 particiones/72, boot_a "ANDROID!" en 0x40000, 4 MiB en 25 ms
  (~160 MB/s). ICE con reloj apagado (0x80004220) no estorba al DMA legacy.
  Layout: particiones dinámicas (super 12288M con system/vendor de ambos slots), userdata
  105227M (inicio LBA 0x1b70000). No hay system_b: para la raíz de iOS hay que reducir
  userdata/crear partición nueva, usar userdata entera, o usar microSD (sdhc_2).

- dd8a193, emmcgpt=1 (PLAN, sin escribir) en el S62, 2026-11-10 21:46. GPT ORIGINAL (para revertir):
  72 entradas, usable 0x22-0xe8f5fde, header backup 0xe8f5fff, entradas 0x2 / 0xe8f5fdf,
  entries CRC 0xf0364600. userdata = entrada #68, 0x1b70000-0xe8f5fde (105227 MiB). Slot libre #69.
  PLAN: userdata -> 0x1b70000-0xc8f57ff (88843 MiB); "ios" HFS+ #69 0xc8f5800-0xe8f5fde
  (16384 MiB); entries CRC nuevo 0x1d8d276f. Revertir = userdata last 0xe8f5fde + vaciar #69.

## Hallazgo útil
- PAGE_RATIO 4: el userland ve páginas de 16K aunque el hardware sea 4K (como los SoC 4K de
  Apple con más de 1GB). Reduce el riesgo de "iOS 16 sobre 4K"; el de LSE/ARMv8.0 sigue.

## Siguiente
1. HECHO: kernel arranca en el teléfono hasta la espera del disco raíz (cpus=1).
2. Driver eMMC (SDHCI sdhc_1 @0xc0c4000) para montar root.
3. Imagen de sistema iOS en userdata (borra Android; confirmar antes) y prueba de userland.
4. Guardar en el repo unas tools propias (ADT/payload/QEMU) en vez de adaptar las de ios-sweet al vuelo.
