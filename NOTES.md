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

- 2026-11-10 21:50: GPT APLICADA en el S62 (emmcgpt=2): 4 escrituras verificadas + revalidación.
  ABL confirma: userdata 0x15B0B00000 (88843 MiB, ext4), ios 0x4000FBE00 (16 GiB).
  userdata formateada ext4 (22743808 bloques de 4K) y metadata borrada con fastboot.
  Android A pendiente de probar (debería arrancar como recién reseteado).
  Raíz de iOS: partición "ios" (boot-arg ufsroot=ios rd=ufsroot0).

- 2026-11-10 23:50-23:53: **iOS 16.7.16 ARRANCA en el S62.** Raíz HFS+ en la partición "ios"
  (iosroot.yml + ios-sweet, cifrada a la clave del usuario, descifrada/verificada en su PC,
  `fastboot -S 256M flash ios`), kernel 8d5b1fb, boot-args rd=ufsroot0 ufsroot=ios ufsrw=1
  rootrw=1 ignition_level=1 launchd_unsecure_cache=1 ... cpus=1 sweetlog=0, sweettouch/keys/usb=0.
  launchd y muchos servicios arrancan y aparece el logo de Apple: el userland de iOS 16 corre en
  el SDM660 (ARMv8.0), riesgo principal descartado (al menos hasta aquí).
  Nota: fastboot de ABL se congela tras el flash grande (como en ios-sweet): usar
  !S62_FASE3_BOOT.bat (solo boot_b + set-active + reboot) tras reiniciar a fastboot.

- **🎉🎉 HITO 2026-11-11 00:08: PANTALLA DE BLOQUEO DE iOS 16 (SpringBoard) EN EL CAT S62.**
  Foto del usuario: reloj/fecha (sin hora real: "Wednesday, December 31 4:18"), fondo, botón de
  cámara; render por CPU sin GPU, cpus=1. bluetoothd y fairplayd reinician en bucle (sin hardware
  Apple), sin CRASH de SpringBoard/backboardd. ~15 min desde el arranque hasta la UI.
  Imagen limpia (sweetfb_noconsole=1): s62-shim/xnu8796/s62-boot-ios-clean.img, !S62_BOOT_LIMPIO.bat.

## Siguientes pasos tras el hito
1. Táctil (Himax hxcommon, I2C 0x48 según dtbo) y botones (PMIC PM660 vía SPMI 0x800f000).
2. Reloj: RTC del PM660 o hora por boot-arg desde el shim.
3. SMP (8 núcleos, PSCI; MPIDR 0x0-0x3, 0x100-0x103) y GIC reescrito en el sitio correcto.
4. Rendimiento eMMC (ya ADMA2) y USB (sweet_usb es para SM7150).

## Hallazgo útil
- PAGE_RATIO 4: el userland ve páginas de 16K aunque el hardware sea 4K (como los SoC 4K de
  Apple con más de 1GB). Reduce el riesgo de "iOS 16 sobre 4K"; el de LSE/ARMv8.0 sigue.

## Siguiente
1. HECHO: kernel arranca en el teléfono hasta la espera del disco raíz (cpus=1).
2. Driver eMMC (SDHCI sdhc_1 @0xc0c4000) para montar root.
3. Imagen de sistema iOS en userdata (borra Android; confirmar antes) y prueba de userland.
4. Guardar en el repo unas tools propias (ADT/payload/QEMU) en vez de adaptar las de ios-sweet al vuelo.

## Entrada: botones y táctil (en curso)

- Botones (`bsd/dev/sweet_keys.c`, reescrito para el S62): árbitro SPMI v3 del SDM660 (core 0x0800f000,
  mapa APID en core+0x800+4n, observer 0x09400000 + 0x8000*apid, EE 0). Solo lecturas EXT_READL.
  PON PM660 RT 0x0810: bit0 KPDPWR (power), bit1 RESIN (DTB stock: linux,code 115 = vol+).
  Mapa por boot-args (código 0x800|bit = PON, 0x0nn = PM660 GPIO n, 0x2nn = PM660L GPIO n, 0 = nada):
  `s62kpwr=0x800 s62kvu=0x801 s62kvd=0x207 s62khome=0x00b` (vol- y home son suposiciones; el driver
  registra cada cambio de cualquier GPIO de PMIC configurado como entrada: "S62 KEYS: gpio pm660l-7 level 0").
- Táctil (`bsd/dev/sweet_touch.c`, reescrito): Himax HX83112A en blsp_i2c1 (QUP 0x0c175000, pines gpio2/3
  función 3), dirección 0x48, IRQ gpio45 (sur), reset gpio25 (norte, no se toca salvo `s62treset=1`).
  QUP v2 en modo FIFO con tags V2, sondeo; eventos de 56 bytes desde el registro 0x30 (formato de
  Linux himax_hx83112b.c). Arranca `sweettouchdelay` s (60 por defecto) después de montar la raíz.
  `s62ti2c=100` baja el bus a 100 kHz. SweetHID usa ahora el tamaño real del panel (1080x2160).

## Táctil: hardware real (de Android 11 en slot A, 2026-11-11)

- La unidad NO es la variante Himax del dtbo viejo guardado en `s62-shim/stock_dtbo.img`. Android real:
  panel `hx8399c boe jutai`, dtbo_idx=7, dtb_idx=1, hwid=1; táctil FocalTech `fts_ts` id 0x5422 en
  i2c-4 (QUP 0x0c178000, gpio14 SDA / gpio15 SCL función 2, tile norte), dirección 0x38,
  irq gpio67, reset gpio66 (gpiochip TLMM base 1166). vdd = `tp_vdd` fijo desde pm660l_bob (3.3 V),
  vcc_i2c = pm660l_l3.
- Los LDO son del RPM (dueño SPMI EE 4): escritura directa imposible. Cliente GLINK-RPM sondeado en
  `sweet_touch.c` (msg RAM 0x778000, TOC "grt0", FIFOs ap2r/r2ap, timbre APCS 0x17911008 bit 0,
  canal `rpm_requests`, petición "req" con kvp swen/uv). Verificado en hardware: verack/openack y
  rc=0 al encender ldob6, ldoa12, ldob3, ldob8.
- gpio12 del TLMM da external abort al leerlo (protegido por TZ): no barrer todos los pines.
- Botones verificados: power = PON KPDPWR, vol- = PON RESIN, vol+ = PM660L GPIO7, home = PM660 GPIO11.
- SMP: 8 núcleos arrancan (MPIDR Aff1 = clúster, Aff0 = núcleo); config SGI/PPI del GICR reescrita tras
  habilitar el GIC en cada CPU.
