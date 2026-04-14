# Boteo en Red Pitaya (Zynq-7000)

> **Referencia principal:** The Zynq Book, Capítulo 24 – *Booting and Configuration* [1]

---

## 1. Inicialización del sistema

El proceso de arranque de cualquier sistema embebido sigue una cadena de responsabilidades progresiva: cada etapa inicializa el hardware necesario para cargar a la siguiente. En el caso del Zynq-7000 (usado en la Red Pitaya), esta cadena está parcialmente implementada en hardware y parcialmente en software.

![Etapas generales de inicialización](https://i.imgur.com/UTcRegh.png)

Las etapas canónicas son las siguientes:

### 1.1 BIOS / BootROM — El arranque desde el silicio

En una PC de escritorio, lo primero que corre al encender es el **[BIOS](https://en.wikipedia.org/wiki/BIOS)** (Basic Input/Output System), un firmware residente en una memoria flash de la placa madre. El BIOS realiza dos tareas en secuencia. La primera es el **[POST](https://en.wikipedia.org/wiki/Power-on_self-test)** (Power-On Self Test): verifica que los componentes básicos del hardware estén presentes y funcionen (RAM, controladores, etc.). Esta prueba sólo ocurre en un arranque en frío (power-on); si el sistema fue reseteado en caliente (warm boot), el BIOS levanta una bandera en memoria y omite el POST para ganar tiempo. La segunda tarea es el **Runtime Service**: el BIOS consulta la lista de dispositivos de arranque configurada en la CMOS (el orden típico es: disco duro → USB → red) y, cuando encuentra un dispositivo booteable, carga el **[Master Boot Record](https://en.wikipedia.org/wiki/Master_boot_record)** (MBR) de ese dispositivo en RAM y le entrega el control.

El **MBR** es el primer sector del dispositivo (512 bytes exactos). Su estructura está estandarizada: los primeros 446 bytes contienen el código del bootloader primario, los siguientes 64 bytes contienen la tabla de particiones (4 entradas de 16 bytes cada una, describen las particiones primarias del disco), y los últimos 2 bytes son la firma de validación `0xAA55`. El código en el MBR es el **FSBL** en el contexto de escritorio.

En el Zynq-7000, el equivalente del BIOS es la **BootROM**: un bloque de código grabado permanentemente en silicio durante la fabricación del chip, imposible de modificar. Su función es leer el modo de arranque configurado en los pines `MIO[8:2]` para determinar el medio (SD, QSPI, JTAG, etc.) y cargar el FSBL desde ese medio hacia la RAM on-chip (OCM).

### 1.2 FSBL – First Stage Boot Loader

En el mundo desktop, el FSBL es el código del MBR. Su tarea es localizar la partición activa en la tabla de particiones, marcar todas las demás como inactivas, cargar el sector de arranque de esa partición activa, y transferirle el control al **SSBL**.

En el Zynq, el FSBL es el primer software ejecutable por el usuario. Corre desde la OCM (256 KB de On-Chip Memory). Su responsabilidad central es inicializar la PS (Processing System): configura el PLL de relojes, los controladores DDR, los periféricos MIO, y opcionalmente programa la PL (FPGA) con un bitstream usando el DevC (Device Configuration interface). Luego, carga el SSBL (U-Boot) en la DDR DRAM, deshabilita la caché y la MMU (porque U-Boot asume que están desactivadas al iniciar), y le transfiere el control.

### 1.3 SSBL – Second Stage Boot Loader (U-Boot / GRUB)

El **SSBL** es la etapa que el usuario suele ver: en un desktop con Linux, es **[GRUB](https://www.gnu.org/software/grub/)** (o el antiguo **[LILO](https://en.wikipedia.org/wiki/LILO_(bootloader))**); en el Zynq, es **[U-Boot](https://docs.u-boot.org/en/latest/)**. Su propósito es presentar un menú de sistemas operativos disponibles, cargar el kernel elegido desde el sistema de archivos, descomprimirlo en memoria, y pasarle el control junto con los parámetros de arranque.

GRUB existe en dos sabores. **LILO** (el más antiguo) necesita conocer los sectores físicos donde está el kernel, lo que lo hace frágil ante cambios en el disco. **GRUB** es más robusto porque entiende sistemas de archivos ext2/ext3 directamente, puede leer y cargar el kernel como un archivo normal, y agrega una etapa intermedia entre el MBR y el menú de arranque para manejar esta complejidad.

**U-Boot** es el SSBL estándar para sistemas embebidos ARM, y es el que usa la Red Pitaya. Xilinx provee una [versión personalizada de U-Boot](https://github.com/Xilinx/u-boot-xlnx) para el Zynq-7000. U-Boot puede configurarse interactivamente a través de su consola serial o automáticamente vía el archivo `uEnv.txt`. Sus tareas al arrancar Linux son: leer `BOOT.BIN`, `uImage`, `devicetree.dtb` y `ramdisk8M.image.gz` desde la partición FAT32, cargarlos en las direcciones de memoria correctas, y ejecutar `bootz` o `bootm` para iniciar el kernel.

### 1.4 Kernel Linux

Con el control del CPU en mano, el kernel realiza una pequeña inicialización de hardware adicional antes de descomprimirse a sí mismo. Una vez descomprimido, se mueve a la memoria alta (la parte de la RAM física no directamente mapeada por las tablas de página del kernel) y comienza a inicializar todos sus subsistemas: configura el stack, activa la paginación de memoria, detecta el tipo de CPU y FPU, inicializa los drivers de dispositivos, y monta el sistema de archivos raíz. Si hay un **ramdisk** presente en memoria (cargado previamente por el SSBL), el kernel lo usa como `rootfs` inicial. Finalmente, lanza el primer proceso de espacio de usuario.

### 1.5 Ramdisk — el sistema de archivos en RAM

El **[ramdisk](https://www.kernel.org/doc/html/latest/filesystems/ramfs-rootfs-initramfs.html)** (o `initramfs`) es una imagen comprimida de un sistema de archivos mínimo que el SSBL carga en RAM junto con el kernel. Su función es resolver el problema del huevo y la gallina: el kernel necesita drivers de sistema de archivos para leer el `rootfs` real que está en la SD ([ext4](https://ext4.wiki.kernel.org/)), pero esos drivers pueden estar compilados como módulos `.ko` dentro del `rootfs` real. El ramdisk provee un entorno mínimo donde el kernel puede encontrar y cargar esos módulos antes de montar el `rootfs` definitivo.

En el Zynq/Red Pitaya el archivo correspondiente se llama típicamente `ramdisk8M.image.gz` (una imagen de 8 MB comprimida con gzip). Contiene un sistema [BusyBox](https://www.busybox.net/) mínimo con los módulos del kernel necesarios para montar la partición ext4. Una vez que el `rootfs` real está montado, el kernel hace un [`pivot_root`](https://man7.org/linux/man-pages/man2/pivot_root.2.html) o `switch_root` y descarta el ramdisk, liberando esa memoria.

> En sistemas muy simples (barebones) o cuando todos los drivers están compilados directamente en el kernel (no como módulos), el ramdisk puede omitirse y el kernel puede montar el `rootfs` de la SD directamente.

### 1.6 Init Process

El primer proceso en espacio de usuario (PID 1), típicamente **[systemd](https://systemd.io/)** o **[BusyBox init](https://www.busybox.net/)**. Se encarga de leer la configuración del sistema (`/etc/inittab` en sistemas SysV, o las unidades de `systemd`), determinar el **runlevel** inicial, montar el resto del sistema de archivos, levantar servicios de red y daemons, y finalmente entregar el sistema al usuario.

[Linux Standard Base](https://refspecs.linuxbase.org/LSB_3.1.1/LSB-Core-generic/LSB-Core-generic/runlevels.html) define 7 runlevels estándar, numerados del 0 al 6. El runlevel 0 apaga el sistema, el 6 lo reinicia, el 1 arranca en modo monousuario (mantenimiento), el 3 es el modo multiusuario con red típico para servidores sin interfaz gráfica, y el 5 agrega display manager gráfico. En la Red Pitaya se usa un sistema de tipo servidor (runlevel 3), sin entorno gráfico.

---

## 2. Boteo específico del Zynq-7000

El Zynq-7000 tiene una arquitectura **PS+PL** (Processing System + Programmable Logic). Esto agrega una dimensión extra al proceso de arranque: la necesidad de programar el FPGA en algún momento de la secuencia.

![Arquitectura PS+PL del Zynq](https://i.imgur.com/ZHoywDc.png)

### 2.1 BootROM y modo de arranque

La BootROM es ejecutada por el CPU ARM Cortex-A9 apenas sale del reset. Lee los pines `MIO[8:2]` para determinar el **Boot Mode**:

| Valor | Modo      | Descripción                             |
|-------|-----------|-----------------------------------------|
| 000   | JTAG      | Arranque por depurador (sin medio)      |
| 001   | QSPI      | Flash SPI de 32/64 MB                  |
| 010   | NOR Flash | Flash paralela                          |
| 101   | SD Card   | Tarjeta SD (el más usado en Red Pitaya) |

En la Red Pitaya, los pines MIO están fijados en PCB para **SD Card boot**.

### 2.2 La imagen `BOOT.BIN`

La BootROM no carga directamente el FSBL como un binario ELF; espera un archivo con formato **Zynq Boot Image**, típicamente llamado `BOOT.BIN`. Este archivo es un contenedor que puede incluir el FSBL (`fsbl.elf`), el bitstream de la PL (`system.bit`) de forma opcional, y el U-Boot (`u-boot.elf`). La herramienta **[Bootgen](https://docs.amd.com/r/en-US/ug1283-bootgen-user-guide)** de Xilinx genera este contenedor a partir de un archivo de descripción [`.bif`](https://docs.amd.com/r/en-US/ug1283-bootgen-user-guide/BIF-File-Syntax) (Boot Image Format).

![Flujo de arranque del Zynq](https://i.imgur.com/7vYUgG7.png)

---

## 3. Archivos de boteo

### 3.1 Estructura de particiones de la SD

El sistema de archivos de la SD se divide en dos particiones. La **Partición 1 ([FAT32](https://en.wikipedia.org/wiki/File_Allocation_Table))** contiene los archivos de arranque que la BootROM y U-Boot pueden leer directamente; FAT32 es necesario porque la BootROM sólo entiende ese sistema de archivos. La **Partición 2 ([ext4](https://ext4.wiki.kernel.org/))** contiene el sistema de archivos raíz (`rootfs`); Linux monta esta partición como `/` durante el arranque.

### 3.2 Sistema mínimo (Barebones)

Un sistema mínimo para verificar que el hardware funciona no requiere un OS completo. Los archivos necesarios en la partición FAT32 son:

```image-layout-a
![Barebones boot files](https://i.imgur.com/YPMuEr7.png)
```

| Archivo          | Origen                    | Descripción                                      |
|------------------|---------------------------|--------------------------------------------------|
| `BOOT.BIN`       | Bootgen (FSBL + U-Boot)   | Contenedor de arranque primario                  |
| `uImage`         | Compilación del kernel    | Imagen del kernel Linux (formato U-Boot)         |
| `devicetree.dtb` | Compilación del DTB       | Descripción del hardware para el kernel          |
| `uEnv.txt`       | Manual / scripts          | Variables de entorno de U-Boot (opcional)        |

### 3.3 Sistema con OS completo

Cuando se agrega un sistema operativo completo (ej. Debian/Ubuntu), la partición ext4 contiene el `rootfs` y la partición FAT32 puede incluir también la imagen `initramfs`:

```image-layout-a
![Full OS boot files](https://i.imgur.com/iQiqmNH.png)
```

| Archivo          | Partición | Descripción                                               |
|------------------|-----------|-----------------------------------------------------------|
| `BOOT.BIN`       | FAT32     | FSBL + bitstream PL + U-Boot                             |
| `uImage`         | FAT32     | Kernel Linux                                              |
| `devicetree.dtb` | FAT32     | Device Tree Blob                                          |
| `initramfs`      | FAT32     | Sistema de archivos inicial (opcional, para pivot_root)   |
| `/` (rootfs)     | ext4      | Sistema Debian/Ubuntu completo                            |

---

## 4. El SSBL: `ssbl.elf` vs `u-boot.elf`

Cuando se habla del segundo eslabón en la cadena de arranque del Zynq, hay una distinción fundamental que suele pasar desapercibida pero que tiene consecuencias concretas en cómo se estructura todo el sistema: no todos los "SSBL" son iguales. En el ecosistema de la Red Pitaya coexisten dos alternativas muy distintas.

### 4.1 `ssbl.elf` — El bootloader mínimo de Pavel Demin

El `ssbl.elf` que aparece en los proyectos de [Pavel Demin](https://github.com/pavel-demin/red-pitaya-notes) **no es una versión simplificada de U-Boot**. Es un bootloader completamente distinto, escrito desde cero con un único propósito: recibir el control del FSBL y saltar al kernel con los parámetros correctos. Su implementación completa es, literalmente, esto:

```c
#include <stdint.h>

// Macro para escribir en registros del SoC mapeados en memoria
#define set(a, v) (*(volatile uint32_t *)(a) = (v))

// Declara un puntero a función en la dirección donde vive el kernel
// en RAM: 0x2008000. Los tres parámetros son los registros r0, r1, r2
// que la convención de boot ARM exige pasar al kernel.
// Ver: https://www.kernel.org/doc/html/latest/arm/booting.html
#define linux ((void (*)(uint32_t, uint32_t, uint32_t))0x2008000)

// 1. Desbloquea el SLCR (System Level Control Registers).
//    El SLCR controla relojes, resets y configuraciones del SoC.
//    La clave mágica 0xDF0D habilita escrituras sobre él.
set(0xF8000008, 0xDF0D);

// 2. Configura la OCM (On-Chip Memory).
//    0x1F mapea los 256 KB de OCM al rango de direcciones alto (0xFFFF0000),
//    liberando el rango bajo (0x00000000-0x0003FFFF) para la DDR.
set(0xF8000910, 0x1F);

// 3. Limpia los filtros de direccionamiento del SCU (Snoop Control Unit).
//    Deshabilita cualquier filtro de seguridad que pueda bloquear
//    accesos del kernel a regiones de memoria.
set(0xF8F00040, 0);

// 4. Salta al kernel. Convención ARM Linux boot:
//    r0 = 0          (reservado, debe ser cero)
//    r1 = 0xFFFFFFFF (Machine ID; -1 indica que se usa Device Tree)
//    r2 = 0x2000000  (dirección física del Device Tree Blob en RAM)
linux(0, 0xFFFFFFFF, 0x2000000);
```

La elegancia de este enfoque es también su limitación fundamental: **el `ssbl.elf` no tiene sistema de archivos**. No entiende [FAT32](https://en.wikipedia.org/wiki/File_Allocation_Table), no puede leer la SD, no sabe qué es `uEnv.txt`. Cuando el FSBL le entrega el control, todo lo que necesita el kernel ya tiene que estar en RAM: la imagen del kernel en `0x2008000` y el DTB en `0x2000000`. Esto implica que **el `BOOT.BIN` que usa este esquema debe contener el kernel y el DTB embebidos dentro de sí mismo**, ya que el `ssbl.elf` no tiene ningún mecanismo para cargarlos desde la SD en tiempo de ejecución. Esto conduce a un sistema monolítico: un solo `BOOT.BIN` gigante que incluye FSBL + kernel + DTB + ssbl.

### 4.2 `u-boot.elf` — El bootloader completo

**[U-Boot](https://docs.u-boot.org/en/latest/)** es el SSBL estándar del ecosistema Linux embebido, mantenido activamente por la comunidad y con soporte oficial de Xilinx para el Zynq-7000. A diferencia del `ssbl.elf`, U-Boot es un programa completo con capacidades propias: entiende sistemas de archivos FAT, ext2/3/4 y UBIFS; implementa una consola serial interactiva; soporta carga por red (TFTP, NFS); puede leer variables de entorno desde un archivo `uEnv.txt` en la SD; soporta múltiples formatos de imagen de kernel (`uImage`, `zImage`, `Image`); y tiene comandos para inspeccionar la memoria, modificar el Device Tree en tiempo de ejecución y depurar problemas de arranque.

La consecuencia directa de estas capacidades es que **el sistema ya no necesita ser monolítico**. El `BOOT.BIN` contiene sólo el FSBL y U-Boot. El kernel, el DTB y el ramdisk viven como archivos separados en la partición FAT32 de la SD, y U-Boot los carga en tiempo de ejecución. **Actualizar el kernel o el Device Tree es tan simple como copiar un nuevo archivo a la SD — sin tocar ni recompilar el `BOOT.BIN`.**

La tabla siguiente resume las diferencias clave:

| Característica                  | `ssbl.elf` (Pavel Demin)              | `u-boot.elf` (Xilinx/community)         |
|---------------------------------|---------------------------------------|-----------------------------------------|
| Tamaño                          | ~50 bytes de código útil              | ~400 KB                                 |
| Lee archivos de la SD           | No                                    | Sí (FAT32, ext4)                        |
| Consola interactiva             | No                                    | Sí (serial, UART)                       |
| `uEnv.txt`                      | No                                    | Sí                                      |
| Carga por red (TFTP/NFS)        | No                                    | Sí                                      |
| Sistema monolítico              | Sí (kernel dentro del BOOT.BIN)       | **No** (kernel como archivo separado)   |
| **Recompilar para cambiar DTB** | **Sí**                                | **No**                                  |
| Complejidad de build            | Mínima                                | Requiere cross-compilación ARM          |
| Flexibilidad en desarrollo      | Baja                                  | Alta                                    |

### 4.3 Construcción de `u-boot.elf` desde fuente

Cuando se opta por U-Boot como SSBL, es necesario compilarlo para la arquitectura ARM del Zynq. Xilinx mantiene un [fork de U-Boot](https://github.com/Xilinx/u-boot-xlnx) con los parches específicos para el Zynq-7000 y un [`defconfig`](https://www.kernel.org/doc/html/latest/kbuild/kconfig.html) ya configurado para la Red Pitaya. El proceso de build se puede expresar como un conjunto de reglas [`make`](https://www.gnu.org/software/make/manual/make.html):

```makefile
## Descarga el tarball del código fuente de U-Boot de Xilinx.
## La URL apunta a una versión específica del fork xilinx/u-boot-xlnx.
$(UBOOT_TAR):
	mkdir -p $(@D)
	curl -L $(UBOOT_URL) -o $@

## Extrae el árbol de fuentes desde el tarball.
## --strip-components=1 elimina el directorio raíz del tar
## (que suele llamarse u-boot-xlnx-xilinx-vYYYY.N) para dejar
## los fuentes directamente en $(UBOOT_DIR).
$(UBOOT_DIR): $(UBOOT_TAR)
	mkdir -p $@
	tar -zxf $< --strip-components=1 --directory=$@

## Configura y compila U-Boot para Zynq-7000 (Red Pitaya defconfig).
##
## Cross-compilación: el host es x86_64 pero el target es ARM.
## El compilador arm-linux-gnueabihf-gcc debe estar instalado:
##   sudo apt install gcc-arm-linux-gnueabihf
##
## La variable CROSS_COMPILE le indica al sistema de build de U-Boot
## qué prefijo usar para todas las herramientas (gcc, ld, objcopy, etc.).
##
## zynq_red_pitaya_defconfig es el archivo de configuración en
## configs/ del árbol de U-Boot. Define qué drivers incluir,
## qué tamaño de stack usar, y decenas de opciones de compilación.
##
## UIMAGE_LOADADDR=0x8000 le indica a U-Boot en qué dirección DDR
## debe cargar la imagen del kernel (uImage). 0x8000 es el valor
## estándar para Zynq: los primeros 32 KB se reservan para datos
## de arranque del kernel ARM.
##
## -j$(nproc) paraleliza la compilación usando todos los cores
## disponibles del host.
##
## El binario resultante 'u-boot' se copia a tmp/u-boot.elf para
## que la regla de Bootgen pueda encontrarlo sin conocer el path
## versionado del directorio de fuentes.
$(UBOOT_ELF): $(UBOOT_DIR)
	$(MAKE) -C $< CROSS_COMPILE=arm-linux-gnueabihf- zynq_red_pitaya_defconfig
	$(MAKE) -C $< CROSS_COMPILE=arm-linux-gnueabihf- UIMAGE_LOADADDR=0x8000 -j$$(nproc)
	cp $</u-boot $@
```

El proceso tiene tres etapas conceptuales. Primero, la **configuración** (`zynq_red_pitaya_defconfig`): U-Boot tiene miles de opciones de compilación gestionadas con el mismo sistema [Kconfig](https://www.kernel.org/doc/html/latest/kbuild/kconfig.html) que el kernel Linux; el `defconfig` provee una selección razonable para la Red Pitaya. Segundo, la **compilación cruzada**: como el host es x86_64 y el target es ARM Cortex-A9, todas las herramientas del toolchain deben tener el prefijo `arm-linux-gnueabihf-`; la "h" en `gnueabihf` indica *hard float*, es decir que la FPU del Cortex-A9 se usará para operaciones de punto flotante en lugar de emularlas por software. Tercero, el **empaquetado**: el ELF resultante se pasa a [Bootgen](https://docs.amd.com/r/en-US/ug1283-bootgen-user-guide) junto con el FSBL (y opcionalmente el bitstream) para construir el `BOOT.BIN` final.

> Vale notar que `UIMAGE_LOADADDR=0x8000` fija la dirección donde U-Boot espera encontrar la imagen del kernel en memoria. Esta dirección tiene que coincidir con la dirección a la que U-Boot copiará el `uImage` cuando lo lea de la SD. Si hay un mismatch entre la dirección de carga y la dirección de entrada del kernel, el sistema arrancará y se colgará silenciosamente justo cuando U-Boot haga el `bootm`.

---

## 5. Bootgen y la generación de `BOOT.BIN`

### 5.1 Qué hace Bootgen

**[Bootgen](https://docs.amd.com/r/en-US/ug1283-bootgen-user-guide)** es la herramienta standalone de Xilinx (incluida con el SDK/Vitis, pero también disponible como binario separado) que toma los distintos componentes del arranque y los empaqueta en un único archivo binario: el `BOOT.BIN`. Este proceso no es simplemente una concatenación de archivos: Bootgen construye una estructura jerárquica precisa que la BootROM del Zynq sabe cómo interpretar.

Concretamente, Bootgen realiza las siguientes operaciones. **Prefija un Boot Image Header:** el header es la primera cosa que lee la BootROM; contiene la tabla de particiones interna del `BOOT.BIN`, los offsets y tamaños de cada componente embebido, y metadatos de autenticación. Sin este header correctamente formado, la BootROM rechaza la imagen. **Empaqueta cada partición en el BIF:** cada archivo listado en el `.bif` se convierte en una "partición" dentro del `BOOT.BIN`; para el FSBL (marcado como `[bootloader]`), Bootgen lo ubica inmediatamente después del header, seguido del bitstream y finalmente el SSBL. **Aplica opcionalmente cifrado y autenticación:** Bootgen puede cifrar cada partición con AES-256 (usando una clave en la eFUSE o BBRAM del chip) y/o agregar certificados RSA/HMAC-SHA256; para Red Pitaya en laboratorio, generalmente se usa arranque no-seguro. **Convierte el bitstream:** los bitstreams de Vivado (`.bit`) contienen un header propio que Bootgen remueve antes de empaquetar el bitstream puro, dado que el DevC del Zynq no lo acepta.

### 5.2 Estructura del Boot Image Format (BIF)

El archivo [`.bif`](https://docs.amd.com/r/en-US/ug1283-bootgen-user-guide/BIF-File-Syntax) es el descriptor que le indica a Bootgen qué incluir y con qué atributos. Su sintaxis es la siguiente:

```
// archivo: boot.bif — caso mínimo (sin bitstream, sin cifrado)
the_ROM_image:
{
    [bootloader] fsbl.elf        // partición 1: FSBL, obligatorio
    u-boot.elf                   // partición 2: U-Boot (SSBL), obligatorio
}
```

```
// archivo: boot.bif — caso completo (con bitstream de la PL)
the_ROM_image:
{
    [bootloader] fsbl.elf        // debe ser siempre la primera partición
    system.bit                   // bitstream: debe ir después del FSBL y antes del SSBL
    u-boot.elf                   // SSBL: debe tener dirección de carga > 1 MB
}
```

Cada atributo entre corchetes `[...]` modifica cómo Bootgen trata esa partición. Los más relevantes son:

| Atributo              | Efecto                                                                 |
|-----------------------|------------------------------------------------------------------------|
| `[bootloader]`        | Marca la partición como el FSBL. Obligatorio para la primera entrada.  |
| `[load=0xNNNNNNNN]`   | Especifica la dirección de carga en memoria DDR para esa partición.    |
| `[startup=0xNNNNNNNN]`| Especifica la dirección de entrada (entry point) donde la CPU saltará. |
| `[encryption=aes]`    | Cifra la partición con AES-256 usando la clave del dispositivo.        |
| `[authentication=rsa]`| Agrega un certificado RSA para verificar la autenticidad.              |
| `[offset=0xNNNN]`     | Ubica la partición en un offset específico dentro del BOOT.BIN.        |
| `[init]`              | Permite incluir un archivo de inicialización de registros PS (`.int`). |

Una restricción crítica: **la dirección de carga del SSBL (U-Boot) debe ser mayor a 1 MB (0x00100000)**. Durante la ejecución del FSBL, la DDR no está completamente mapeada y las direcciones por debajo de 1 MB no son accesibles. Si U-Boot se compila para cargar por debajo de ese límite, el FSBL lo escribirá en una dirección que luego el CPU no puede leer, y el sistema se colgará silenciosamente.

La estructura interna del `BOOT.BIN` resultante tiene la forma general:

```
BOOT.BIN
├── Boot Image Header            ← leído por la BootROM al arrancar
│     ├── Boot ROM header
│     ├── Register Initialisation  (configura relojes/pins antes del FSBL)
│     ├── Image Header Table
│     └── Partition Header Table   (offsets, tamaños, atributos de cada partición)
│
├── Partición 1: FSBL (.elf)     ← cargado a la OCM por la BootROM
├── Partición 2: Bitstream (.bit) ← programado en la PL por el FSBL (opcional)
└── Partición 3: U-Boot (.elf)   ← cargado a la DDR por el FSBL
```

El comando de invocación de Bootgen es:

```bash
bootgen -image boot.bif -arch zynq -o BOOT.BIN
```

> **Nota para Red Pitaya:** El proyecto oficial de Pavel Demin genera `BOOT.BIN` automáticamente dentro del flujo de build de Vivado/Vitis. Los scripts `image.sh` y `debian.sh` asumen que este archivo ya existe o lo descargan de las *releases* del repositorio.

---

## 6. Scripts de construcción: `image.sh` y `debian.sh`

El proyecto de Red Pitaya (basado en el trabajo de **[Pavel Demin](https://github.com/pavel-demin/red-pitaya-notes)**) utiliza dos scripts principales para construir la imagen completa de la SD. Ambos están pensados para correr en un host Linux (Ubuntu/Debian) con acceso a `chroot` y a las herramientas de cross-compilación ARM.

### 6.1 `debian.sh` — Construcción del sistema de archivos raíz

Este script construye el `rootfs` Debian/Ubuntu para ARM usando [`debootstrap`](https://wiki.debian.org/Debootstrap). Su flujo general es:

```bash
#!/bin/bash
# Fragmento ilustrativo de debian.sh

ROOTFS_DIR=rootfs
ARCH=armhf
SUITE=bookworm   # o jammy, focal, etc.

# 1. Primera pasada: descarga el esqueleto de Debian para ARM
debootstrap --arch=$ARCH --foreign $SUITE $ROOTFS_DIR

# 2. Copia el binario de QEMU para emulación del chroot en x86
cp /usr/bin/qemu-arm-static $ROOTFS_DIR/usr/bin/

# 3. Segunda pasada dentro del chroot (ejecutada por QEMU)
chroot $ROOTFS_DIR /debootstrap/debootstrap --second-stage

# 4. Configura locale, hostname, usuarios, red, etc.
chroot $ROOTFS_DIR bash -c "echo 'redpitaya' > /etc/hostname"

# 5. Instala paquetes adicionales
chroot $ROOTFS_DIR apt-get install -y \
    openssh-server python3 nginx ...

# 6. Aplica parches (ver §7)
```

La dependencia de [`qemu-arm-static`](https://www.qemu.org/) es clave: permite ejecutar binarios ARM en un host x86_64, lo que hace posible el `chroot` cruzado sin necesitar hardware real.

### 6.2 `image.sh` — Armado de la imagen `.img`

Una vez que el `rootfs` existe, `image.sh` crea la imagen de disco completa que luego se graba en la SD:

```bash
#!/bin/bash
# Fragmento ilustrativo de image.sh

IMG=redpitaya_os.img
SIZE_MB=3800

# 1. Crea un archivo vacío del tamaño de la imagen
dd if=/dev/zero of=$IMG bs=1M count=$SIZE_MB

# 2. Crea la tabla de particiones (MBR)
parted -s $IMG mklabel msdos
parted -s $IMG mkpart primary fat32 4MiB 128MiB   # boot
parted -s $IMG mkpart primary ext4  128MiB 100%   # rootfs

# 3. Monta las particiones con loopback
LODEV=$(losetup --find --show --partscan $IMG)
mkfs.vfat -F 32 -n boot  ${LODEV}p1
mkfs.ext4 -L rootfs       ${LODEV}p2

# 4. Copia los archivos de boot a la partición FAT32
mount ${LODEV}p1 /mnt/boot
cp BOOT.BIN uImage devicetree.dtb /mnt/boot/
umount /mnt/boot

# 5. Copia el rootfs a la partición ext4
mount ${LODEV}p2 /mnt/rootfs
rsync -a rootfs/ /mnt/rootfs/
umount /mnt/rootfs

# 6. Libera el dispositivo loopback
losetup -d $LODEV
```

El resultado final es un archivo `.img` listo para grabar con [balena-Etcher](https://etcher.balena.io/) o `dd`.

---

## 7. Parches del sistema

El proyecto de Pavel Demin aplica una serie de parches sucesivos sobre el kernel de Linux y el Device Tree para adaptar el hardware genérico de Zynq a la Red Pitaya. Los parches se encuentran en el directorio `patches/` del repositorio y se aplican dentro del script `debian.sh`.

### 7.1 Estructura de los parches

Los parches siguen el formato estándar [`git diff`](https://git-scm.com/docs/git-diff) y se aplican con:

```bash
patch -p1 < patches/0001-nombre-del-parche.patch
```

El orden de aplicación importa: cada parche asume que los anteriores ya fueron aplicados.

### 7.2 Parche CMA (Contiguous Memory Allocator)

El parche más importante para la Red Pitaya es el que configura el **[CMA](https://www.kernel.org/doc/html/latest/mm/dma-api-howto.html)** (Contiguous Memory Allocator). La Red Pitaya usa la PL para adquisición de datos de alta velocidad (ADC/DAC a 125 MSPS) y esos datos necesitan ser transferidos a la PS mediante DMA. El DMA requiere regiones de memoria **físicamente contiguas**, algo que el allocator normal de Linux no puede garantizar en tiempo de ejecución.

El parche CMA modifica el [Device Tree](https://www.devicetree.org/) (o los parámetros del kernel) para **reservar** una región de memoria contigua en el arranque, antes de que el kernel la fragmente:

```dts
/* Fragmento del DTS con el parche CMA aplicado */
/ {
    reserved-memory {
        #address-cells = <1>;
        #size-cells = <1>;
        ranges;

        cma_pool: linux,cma {
            compatible = "shared-dma-pool";
            reusable;
            size = <0x2000000>;      /* 32 MB reservados */
            alignment = <0x2000000>;
            linux,cma-default;
        };
    };
};
```

Alternativamente, el CMA puede configurarse en los `bootargs` de U-Boot:

```
bootargs = "... cma=32M"
```

> **¿Por qué es crítico?** Sin este parche, el driver de DMA de la PL fallará intermitentemente al no encontrar bloques de memoria física contigua suficientemente grandes, especialmente después de que el sistema lleva tiempo corriendo y la memoria está fragmentada.

### 7.3 Otros parches relevantes

Además del CMA, el proyecto típicamente incluye parches para el **overclock del ARM Cortex-A9** (la Red Pitaya puede correr a 666 MHz o 800 MHz según la revisión de hardware), la **configuración de los MIO/EMIO** (mapeo de los pines físicos a las funciones del Zynq), los **drivers de la PL** (módulos del kernel para acceder a los registros AXI desde el espacio de usuario vía `/dev/mem` o drivers dedicados), y la **configuración de la red** (MAC address fija basada en el ID único del chip).

---

## 8. Device Tree — Árbol de dependencias

El **[Device Tree](https://www.devicetree.org/)** (DT) es una estructura de datos jerárquica que describe el hardware de la plataforma al kernel Linux. A diferencia de x86 donde el hardware se descubre dinámicamente (PCI, ACPI), en sistemas embebidos ARM el hardware no es auto-descriptible, y el DT cumple ese rol.

### 8.1 Fuentes del Device Tree

El Device Tree tiene tres niveles de fuentes que se combinan durante la compilación:

```
                    ┌────────────────────────────────┐
                    │  Árbol de Inclusión del DTS     │
                    └────────────────────────────────┘
                                   │
        ┌──────────────────────────┼──────────────────────────┐
        ▼                          ▼                          ▼
 zynq-7000.dtsi            pl.dtsi (generado           system-user.dtsi
 (SoC genérico,            por Vivado para            (personalizaciones
  upstream Linux)           la PL específica)          del usuario)
```

El **`zynq-7000.dtsi`** describe los periféricos del PS (UART, I2C, SPI, DDR, Ethernet, etc.) y se encuentra en el árbol del kernel Linux upstream en `arch/arm/boot/dts/`. El **`pl.dtsi`** describe los bloques IP instanciados en la PL (AXI GPIO, AXI DMA, AXI Interconnect, etc.) y lo genera automáticamente Vivado al exportar el hardware. El **`system-user.dtsi`** es un archivo de personalizaciones adicionales: configuración de CMA, parámetros de red, alias, etc.

### 8.2 Árbol de dependencias para Red Pitaya

```
system-top.dts
    │
    ├── include: zynq-7000.dtsi          (kernel: arch/arm/boot/dts/)
    │       │
    │       ├── cpu@0 (Cortex-A9 #0)
    │       ├── cpu@1 (Cortex-A9 #1)
    │       ├── ps7_ddr (DDR controller)
    │       ├── ps7_uart_1 (debug UART)
    │       ├── ps7_gem_0 (GigE Ethernet)
    │       ├── ps7_sd_0 (SD/MMC controller)
    │       ├── ps7_i2c_0 (I2C bus)
    │       ├── ps7_spi_0 (SPI bus)
    │       └── ps7_usb_0 (USB OTG)
    │
    ├── include: pl.dtsi                  (generado por Vivado)
    │       │
    │       ├── axi_gpio_0 (LEDs / botones de la PL)
    │       ├── axi_dma_0 (DMA hacia/desde ADC)
    │       ├── axi_bram_ctrl (BRAM compartida PS-PL)
    │       └── rp_adc (IP personalizado de Red Pitaya)
    │
    └── include: system-user.dtsi         (personalizaciones)
            │
            ├── reserved-memory (CMA, ver §7.2)
            ├── aliases (serial0 → uart1)
            └── chosen (bootargs: console, root, cma)
```

### 8.3 Compilación del DTS a DTB

El Device Tree Source (`.dts`) se compila a Device Tree Blob (`.dtb`) con el **[Device Tree Compiler](https://git.kernel.org/pub/scm/utils/dtc/dtc.git)** (`dtc`):

```bash
# Compilar DTS → DTB
dtc -I dts -O dtb -o devicetree.dtb system-top.dts

# También puede hacerse desde el directorio del kernel:
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- dtbs
```

El `.dtb` resultante es el archivo que U-Boot carga en memoria y le pasa al kernel al momento del arranque.

---

## 9. Construcción de la SD

Hay dos formas de grabar la imagen en la SD: la vía sencilla para usuarios nuevos (balena-Etcher con una `.img`) y la vía manual para usuarios que quieren control total sobre el proceso.

### 9.1 Vía Novatos: balena-Etcher con una `.img`

Este método requiere que el proceso de build haya generado un único archivo `.img` que contenga ambas particiones. El script `image.sh` (ver §6.2) produce exactamente eso.

**Pasos:**

1. Descargar la imagen `.img` de la sección *Releases* del repositorio, o generarla localmente con `image.sh`.
2. Descargar e instalar [balena-Etcher](https://etcher.balena.io/).
3. Insertar la tarjeta SD (mínimo 4 GB, recomendado 8 GB o más, clase 10).
4. En Etcher: seleccionar la imagen `.img` → seleccionar la tarjeta SD → *Flash*.

> ⚠️ **Advertencia:** Etcher sobreescribe completamente el disco. Verificar que el dispositivo seleccionado es la SD y **no** el disco del sistema.

Una vez terminado el flash, la SD está lista para insertar en la Red Pitaya y encender.

---

### 9.2 Vía Experimentados: particionado manual

Este método es útil cuando se quiere actualizar sólo algunos archivos sin regrabar toda la imagen, o cuando se construye la SD desde cero en el flujo de desarrollo.

#### 9.2.1 Identificar la SD

```bash
# Listar los dispositivos de bloque para identificar la SD
lsblk

# Ejemplo de salida:
# NAME   MAJ:MIN RM   SIZE RO TYPE MOUNTPOINT
# sda      8:0    0 500G  0 disk   (disco del sistema)
# sdb      8:16   1   8G  0 disk   ← la SD
#   sdb1   8:17   1 124M  0 part
#   sdb2   8:18   1 7.9G  0 part
```

En los comandos siguientes se asume que la SD es `/dev/sdb`. **Reemplazar por el dispositivo correcto**.

#### 9.2.2 Crear la tabla de particiones

```bash
# Desmontar si está montada
sudo umount /dev/sdb1 2>/dev/null
sudo umount /dev/sdb2 2>/dev/null

# Borrar la tabla de particiones existente y crear una nueva MBR
sudo parted /dev/sdb --script mklabel msdos

# Partición 1: FAT32, 128 MB, para archivos de boot
sudo parted /dev/sdb --script mkpart primary fat32 4MiB 132MiB

# Partición 2: ext4, resto del disco, para rootfs
sudo parted /dev/sdb --script mkpart primary ext4 132MiB 100%

# Formatear las particiones
sudo mkfs.vfat -F 32 -n BOOT   /dev/sdb1
sudo mkfs.ext4 -L rootfs        /dev/sdb2
```

> El offset inicial de 4 MiB en la primera partición reserva espacio para el MBR y alinea correctamente las particiones para rendimiento óptimo en la SD.

#### 9.2.3 Cargar los archivos de boot (partición FAT32)

```bash
# Montar la partición de boot
sudo mkdir -p /mnt/sd_boot
sudo mount /dev/sdb1 /mnt/sd_boot

# Copiar los archivos necesarios
sudo cp BOOT.BIN          /mnt/sd_boot/
sudo cp uImage            /mnt/sd_boot/
sudo cp devicetree.dtb    /mnt/sd_boot/

# Opcional: variables de entorno de U-Boot
sudo cp uEnv.txt          /mnt/sd_boot/

sudo umount /mnt/sd_boot
```

#### 9.2.4 Cargar el sistema de archivos raíz (partición ext4)

```bash
# Montar la partición rootfs
sudo mkdir -p /mnt/sd_rootfs
sudo mount /dev/sdb2 /mnt/sd_rootfs

# Descomprimir/copiar el rootfs
# Opción A: desde un tarball
sudo tar -xzpf rootfs.tar.gz -C /mnt/sd_rootfs/

# Opción B: si el rootfs ya está en un directorio local
sudo rsync -a --progress rootfs/ /mnt/sd_rootfs/

# Sincronizar y desmontar
sync
sudo umount /mnt/sd_rootfs
```

#### 9.2.5 Verificación final

```bash
# Verificar que la partición FAT32 tiene los archivos esperados
sudo mount /dev/sdb1 /mnt/sd_boot
ls -lh /mnt/sd_boot/
# Debe mostrar: BOOT.BIN  devicetree.dtb  uImage  (y opcionalmente uEnv.txt)
sudo umount /mnt/sd_boot

# Verificar el estado de la ext4
sudo e2fsck -n /dev/sdb2
```

La SD está lista. Insertar en la Red Pitaya, conectar un cable serial a la UART de debug (115200 8N1) para ver el output del boot, y encender.

---

## Referencias

[1]: The Zynq Book – *Embedded Processing with the ARM Cortex-A9 on the Xilinx Zynq-7000 All Programmable SoC*, Capítulo 24: Booting and Configuration.  
[2]: Xilinx UG585 – [Zynq-7000 SoC Technical Reference Manual](https://docs.amd.com/r/en-US/ug585-zynq-7000-trm).  
[3]: Pavel Demin – [Red Pitaya ecosystem scripts](https://github.com/pavel-demin/red-pitaya-notes).  
[4]: Xilinx UG1283 – [Bootgen User Guide](https://docs.amd.com/r/en-US/ug1283-bootgen-user-guide).  
[5]: Linux Kernel Documentation – [Device Tree Usage](https://www.kernel.org/doc/html/latest/devicetree/usage-model.html).  
[6]: Linux Kernel Documentation – [ARM Booting](https://www.kernel.org/doc/html/latest/arm/booting.html).
