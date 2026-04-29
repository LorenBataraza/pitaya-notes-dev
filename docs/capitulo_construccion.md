# Construcción del Proyecto Red Pitaya

> **Prerequisito:** Este capítulo asume familiaridad con el proceso de boteo del Zynq descrito en *Booting_RedPitaya.md*. Las referencias a FSBL, U-Boot, Device Tree y `BOOT.BIN` se explican en detalle en ese documento.

---

## 1. Vista General del Flujo de Construcción

El proceso de construcción transforma código fuente RTL, configuraciones del sistema y software en una imagen booteable para la Red Pitaya. El flujo completo tiene siete etapas:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        FLUJO DE CONSTRUCCIÓN                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────┐    ┌───────────┐    ┌───────────┐    ┌───────────────────┐   │
│  │ cores/*.v│───►│tmp/cores/*│───►│ Block     │───►│ .gen/sources_1/   │   │
│  │ (RTL)    │    │(IP Catalog)    │ Design    │    │ bd/system/ip/     │   │
│  └──────────┘    └───────────┘    └───────────┘    └───────────────────┘   │
│       │              ▲                  │                   │              │
│       │         core.tcl                │                   │              │
│       │                           project.tcl               │              │
│       │                                                     ▼              │
│       │                                             ┌───────────────┐      │
│       │                                             │ Synthesis     │      │
│       │                                             │ Implementation│      │
│       │                                             │ Bitstream     │      │
│       │                                             └───────┬───────┘      │
│       │                                                     │              │
│       ▼                                                     ▼              │
│  ┌──────────┐    ┌───────────┐    ┌───────────┐    ┌───────────────┐      │
│  │ U-Boot   │───►│ FSBL      │───►│ Bootgen   │───►│ BOOT.BIN      │      │
│  │ zImage   │    │ DTB       │    │ (.bif)    │    │               │      │
│  │ initrd   │    │ bitstream │    │           │    │               │      │
│  └──────────┘    └───────────┘    └───────────┘    └───────────────┘      │
│                                                            │               │
│                                                            ▼               │
│                                                    ┌───────────────┐       │
│                                                    │ image.sh      │       │
│                                                    │ (SD card .img)│       │
│                                                    └───────────────┘       │
└─────────────────────────────────────────────────────────────────────────────┘
```

Las siete etapas son:

| Etapa | Entrada | Salida | Herramienta |
|-------|---------|--------|-------------|
| 1. IP Packaging | `cores/*.v` | `tmp/cores/*/component.xml` | `scripts/core.tcl` |
| 2. Block Design | IPs + constraints | `.xpr` project | `projects/*/project.tcl` |
| 3. Bitstream | Block Design | `system.bit` | Vivado |
| 4. Hardware Export | Implementación | `.xsa` | Vivado |
| 5. Device Tree | `.xsa` + `device-tree-xlnx` | `devicetree.dtb` | XSCT |
| 6. Boot Image | FSBL + bitstream + U-Boot | `BOOT.BIN` | Bootgen |
| 7. SD Image | BOOT.BIN + zImage + rootfs | `.img` | `scripts/image.sh` |

---

## 2. Estructura del Repositorio

```
red-pitaya-dev/
├── cfg/                          # Constraints de síntesis
│   ├── clocks.xdc               # Definiciones de clock
│   ├── ports.xdc                # Asignaciones de pines físicos
│   └── ports.tcl                # Puertos lógicos del Block Design
│
├── cores/                        # RTL fuente de los IP cores
│   ├── axi_hub.v                # Hub de configuración AXI-Lite
│   ├── axis_trigger.v          # Detector de trigger
│   ├── axis_scope.v            # Adquisición con ventana
│   ├── axis_ram_writer.v       # Escritor DMA a memoria
│   └── ...                      # Otros IP cores
│
├── projects/                     # Definiciones de proyectos Vivado
│   ├── led_blinker/
│   │   └── project.tcl          # Script de creación del proyecto
│   ├── multi_trigger_adc/
│   │   └── project.tcl
│   └── ...
│
├── scripts/                      # Scripts de construcción
│   ├── core.tcl                 # Empaqueta RTL como IP
│   ├── project.tcl              # Crea proyecto Vivado base
│   ├── bitstream.tcl            # Genera bitstream
│   ├── hwdef.tcl                # Exporta .xsa
│   ├── devicetree.tcl           # Genera Device Tree
│   └── fsbl.tcl                 # Compila FSBL
│
├── patches/                      # Parches para kernel/U-Boot
│   ├── linux-6.12.patch
│   ├── zynq-red-pitaya.dts
│   └── ...
│
├── tmp/                          # Artefactos generados
│   ├── cores/                   # IPs empaquetados
│   ├── <project>/               # Proyecto Vivado
│   └── ...
│
└── Makefile                      # Orquestador principal
```

---

## 3. Etapa 1: Empaquetado de IP Cores

### 3.1 Propósito

Vivado requiere que cada módulo RTL personalizado esté "empaquetado" como un IP core con metadatos XML antes de instanciarlo en un Block Design. El empaquetado define las interfaces AXI del módulo, sus parámetros configurables y las dependencias de archivos.

### 3.2 El Script `core.tcl`

El script `scripts/core.tcl` automatiza el empaquetado:

```tcl
# scripts/core.tcl
# Uso: vivado -mode batch -source core.tcl -tclargs <core_name> <part>

set core_name [lindex $argv 0]
set part_name [lindex $argv 1]

set core_dir tmp/cores/${core_name}_v1_0

file mkdir $core_dir
file copy -force cores/${core_name}.v $core_dir/

create_project -force -part $part_name $core_name $core_dir

add_files $core_dir/${core_name}.v

ipx::package_project -root_dir $core_dir -vendor user.org \
    -library user -taxonomy /UserIP -force

set core [ipx::current_core]

# Detectar y asociar interfaces automáticamente
ipx::infer_bus_interfaces xilinx.com:interface:axis_rtl:1.0 $core
ipx::infer_bus_interfaces xilinx.com:interface:aximm_rtl:1.0 $core

# Generar archivos finales
ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::save_core $core

close_project
```

### 3.3 Regla del Makefile

```makefile
PART = xc7z010clg400-1
VIVADO = vivado -mode batch -notrace

tmp/cores/%: cores/%.v
	mkdir -p $(@D)
	$(VIVADO) -source scripts/core.tcl -tclargs $* $(PART)
```

### 3.4 Salida

Para un core `axis_trigger.v`, la estructura generada es:

```
tmp/cores/axis_trigger_v1_0/
├── axis_trigger.v              # Copia del RTL
├── component.xml               # Metadatos del IP
├── xgui/                       # Interfaz de configuración
│   └── axis_trigger_v1_0.tcl
└── bd/                         # (opcional) Block Design wrapper
```

---

## 4. Etapa 2: Creación del Proyecto

### 4.1 Jerarquía de Scripts TCL

Cada proyecto tiene su propio `project.tcl` que invoca un script base compartido:

```
projects/multi_trigger_adc/project.tcl
        │
        └──────► scripts/project.tcl (compartido)
                        │
                        ├── Crea proyecto Vivado
                        ├── Agrega IP repository (tmp/cores)
                        └── Crea Block Design vacío
```

### 4.2 Script Base `scripts/project.tcl`

```tcl
# scripts/project.tcl
# Uso: vivado -mode batch -source project.tcl -tclargs <project_name> <part>

set project_name [lindex $argv 0]
set part_name [lindex $argv 1]

set project_path tmp/$project_name

file delete -force $project_path
create_project $project_name $project_path -part $part_name -force

set_property IP_REPO_PATHS tmp/cores [current_project]
update_ip_catalog

# Crear Block Design base llamado "system"
create_bd_design system

# El script del proyecto específico continúa desde aquí
```

### 4.3 Script del Proyecto `projects/multi_trigger_adc/project.tcl`

```tcl
# projects/multi_trigger_adc/project.tcl

# Importar configuración base
source projects/multi_trigger_adc/block_design.tcl

# Agregar constraints
add_files -fileset constrs_1 -norecurse cfg/clocks.xdc
add_files -fileset constrs_1 -norecurse cfg/ports.xdc

# Configurar el top-level
set_property top system_wrapper [current_fileset]

# Generar wrapper HDL
make_wrapper -files [get_files system.bd] -top
add_files -norecurse [glob $project_path/*.srcs/sources_1/bd/system/hdl/*.v]
```

---

## 5. Etapa 3: Block Design

### 5.1 Componentes del Sistema

El Block Design `system.bd` interconecta los IP cores con el Processing System (PS) del Zynq:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           BLOCK DESIGN                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────┐     │
│  │                    ZYNQ PS (processing_system7)                │     │
│  │                                                                │     │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────────────┐   │     │
│  │  │ M_AXI_  │  │ M_AXI_  │  │ S_AXI_  │  │ FCLK_CLK0       │   │     │
│  │  │ GP0     │  │ GP1     │  │ HP0     │  │ (125 MHz)       │   │     │
│  │  └────┬────┘  └────┬────┘  └────┬────┘  └────────┬────────┘   │     │
│  └───────┼───────────┼────────────┼─────────────────┼────────────┘     │
│          │           │            │                 │                   │
│          ▼           │            ▼                 │                   │
│  ┌───────────────┐   │    ┌───────────────┐         │                   │
│  │ AXI Intercon  │   │    │ AXI Intercon  │         │                   │
│  │ (periféricos) │   │    │ (memoria HP)  │         │                   │
│  └───────┬───────┘   │    └───────┬───────┘         │                   │
│          │           │            │                 │                   │
│   ┌──────┴──────┐    │            │                 │                   │
│   ▼             ▼    ▼            │                 ▼                   │
│ ┌─────┐    ┌─────────────┐        │         ┌─────────────┐             │
│ │ ADC │───►│  axi_hub    │        │         │ clk_wiz     │             │
│ │ SPI │    │  (cfg/sts)  │        │         │ (PLL)       │             │
│ └─────┘    └──────┬──────┘        │         └─────────────┘             │
│                   │               │                                     │
│   cfg_data[N:0]   │   sts_data[M:0]                                     │
│         │         │         ▲                                           │
│         ▼         ▼         │                                           │
│  ┌────────────────────────────────────────────────┐                     │
│  │              ACQUISITION CHAIN                 │                     │
│  │  ┌─────────┐   ┌─────────┐   ┌──────────────┐  │                     │
│  │  │ trigger │──►│  scope  │──►│  ram_writer  │──┼────► S_AXI_HP0      │
│  │  └─────────┘   └─────────┘   └──────────────┘  │                     │
│  └────────────────────────────────────────────────┘                     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 5.2 El Hub de Configuración

El `axi_hub` es el puente entre el software (PS) y el hardware (PL). Expone dos buses:

- **cfg (Configuration)**: Registros de escritura desde el PS hacia la PL
- **sts (Status)**: Registros de lectura desde la PL hacia el PS

```
             PS (software)
                  │
                  │ AXI-Lite (M_AXI_GP0)
                  ▼
           ┌─────────────┐
           │   axi_hub   │
           │             │
           │ BASE: 0x4000_0000 (cfg)
           │ BASE: 0x4100_0000 (sts)
           │             │
           └──────┬──────┘
                  │
        ┌─────────┴─────────┐
        │                   │
   cfg_data[N-1:0]    sts_data[M-1:0]
        │                   ▲
        ▼                   │
   [registros RW]     [registros RO]
```

### 5.3 Mapa de Registros para `multi_trigger_adc`

**Base de Configuración: `0x4000_0000`**

| Offset | Nombre | Bits | R/W | Descripción |
|--------|--------|------|-----|-------------|
| 0x00 | control | [0] | RW | enable: 1=sistema activo |
| | | [1] | RW | arm: pulso inicia captura |
| 0x02 | trig_mode | [1:0] | RW | 0=rising, 1=falling, 2=both |
| 0x04 | trig_threshold | [15:0] | RW | Umbral en unidades ADC (signed) |
| 0x06 | trig_mask | [1:0] | RW | Máscara de canales: bit0=CH0, bit1=CH1 |
| 0x08 | pre_samples | [15:0] | RW | Muestras antes del trigger - 1 |
| 0x0A | post_samples | [15:0] | RW | Muestras después del trigger - 1 |
| 0x0C | base_addr | [31:0] | RW | Dirección base DDR para DMA |
| 0x10 | buffer_size | [31:0] | RW | Tamaño del buffer en bytes |

**Base de Estado: `0x4100_0000`**

| Offset | Nombre | Bits | R/W | Descripción |
|--------|--------|------|-----|-------------|
| 0x00 | status | [0] | R | busy: 1=captura en progreso |
| | | [1] | R | done: 1=captura completada |
| | | [2] | R | error: 1=error de DMA |
| 0x04 | trigger_pos | [31:0] | R | Posición del trigger en el buffer |
| 0x08 | samples_written | [31:0] | R | Muestras escritas a memoria |

---

## 6. Etapa 4-5: Hardware Export y Device Tree

### 6.1 Exportar Hardware Definition

Después de la implementación, Vivado exporta un archivo `.xsa` que contiene:
- El bitstream (opcional)
- La descripción del hardware (direcciones base, interrupciones, etc.)
- Metadatos para generar FSBL y Device Tree

```makefile
tmp/%.xsa: tmp/%.bit
	$(VIVADO) -source scripts/hwdef.tcl -tclargs $*
```

### 6.2 Generar Device Tree

El Device Tree describe el hardware al kernel Linux. El script `devicetree.tcl` usa XSCT (Xilinx Software Command-line Tool):

```tcl
# scripts/devicetree.tcl
set project_name [lindex $argv 0]
set proc_name [lindex $argv 1]
set dtree_dir [lindex $argv 2]

hsi open_hw_design tmp/${project_name}.xsa
hsi set_repo_path $dtree_dir
hsi create_sw_design device-tree -os device_tree -proc $proc_name
hsi generate_target -dir tmp/${project_name}.tree
```

El Device Tree generado incluye nodos para cada IP core con dirección AXI:

```dts
/* Fragmento generado automáticamente */
axi_hub_0: axi_hub@40000000 {
    compatible = "generic-uio";
    reg = <0x40000000 0x10000>;
};

axis_ram_writer_0: axis_ram_writer@40010000 {
    compatible = "generic-uio";
    reg = <0x40010000 0x10000>;
    interrupt-parent = <&intc>;
    interrupts = <0 29 4>;  /* IRQ F2P[0] */
};
```

---

## 7. Etapa 6: Generación de BOOT.BIN

### 7.1 Componentes

El archivo `BOOT.BIN` combina tres componentes (ver *Booting_RedPitaya.md §5*):

1. **FSBL** (`fsbl.elf`): Inicializa PS, programa PL
2. **Bitstream** (`system.bit`): Configuración de la FPGA
3. **U-Boot** (`u-boot.elf`): Bootloader secundario

### 7.2 Archivo BIF

```bif
// tmp/boot.bif
the_ROM_image:
{
    [bootloader] tmp/multi_trigger_adc.fsbl/executable.elf
    tmp/multi_trigger_adc.bit
    tmp/u-boot.elf
}
```

### 7.3 Regla del Makefile

```makefile
tmp/boot.bin: tmp/$(PROJECT).fsbl/executable.elf tmp/$(PROJECT).bit tmp/u-boot.elf
	bootgen -image tmp/boot.bif -arch zynq -o $@
```

---

## 8. Etapa 7: Imagen de SD Card

### 8.1 Contenido de la Partición FAT32

```
/boot/
├── BOOT.BIN          # FSBL + bitstream + U-Boot
├── uImage            # Kernel Linux comprimido
├── devicetree.dtb    # Device Tree compilado
└── uEnv.txt          # Variables de entorno U-Boot
```

### 8.2 Contenido de la Partición ext4

```
/rootfs/
├── bin/
├── etc/
├── home/
├── lib/
│   └── modules/      # Módulos del kernel
├── opt/
│   └── redpitaya/    # Aplicaciones del proyecto
├── usr/
└── var/
```

---

## 9. Makefile Principal

### 9.1 Variables de Configuración

```makefile
# Configuración del proyecto
PROJECT ?= multi_trigger_adc
PART = xc7z010clg400-1
PROC = ps7_cortexa9_0

# Rutas de herramientas
VIVADO = vivado -mode batch -notrace -source scripts/
XSCT = xsct
BOOTGEN = bootgen

# Versiones de dependencias externas
LINUX_TAG = 6.12
UBOOT_TAG = xlnx_rebase_v2024.01_2024.1
DTREE_TAG = xilinx_v2024.1
```

### 9.2 Targets Principales

```makefile
# Target por defecto: generar imagen completa
all: tmp/$(PROJECT).img

# Dependencias de cores (detecta automáticamente todos los .v)
CORES = $(wildcard cores/*.v)
CORE_TARGETS = $(patsubst cores/%.v,tmp/cores/%,$(CORES))

# Empaquetar todos los cores
cores: $(CORE_TARGETS)

# Crear proyecto Vivado
tmp/$(PROJECT).xpr: $(CORE_TARGETS) | cores
	$(VIVADO) project.tcl -tclargs $(PROJECT) $(PART)

# Generar bitstream
tmp/$(PROJECT).bit: tmp/$(PROJECT).xpr
	$(VIVADO) bitstream.tcl -tclargs $(PROJECT)

# Exportar hardware
tmp/$(PROJECT).xsa: tmp/$(PROJECT).bit
	$(VIVADO) hwdef.tcl -tclargs $(PROJECT)

# Device Tree
tmp/$(PROJECT).tree/system-top.dts: tmp/$(PROJECT).xsa $(DTREE_DIR)
	$(XSCT) scripts/devicetree.tcl $(PROJECT) $(PROC) $(DTREE_DIR)

# FSBL
tmp/$(PROJECT).fsbl/executable.elf: tmp/$(PROJECT).xsa
	$(XSCT) scripts/fsbl.tcl $(PROJECT) $(PROC)

# Boot image
tmp/boot.bin: tmp/$(PROJECT).fsbl/executable.elf tmp/$(PROJECT).bit tmp/u-boot.elf
	echo "the_ROM_image: { [bootloader] $< tmp/$(PROJECT).bit tmp/u-boot.elf }" > tmp/boot.bif
	$(BOOTGEN) -image tmp/boot.bif -arch zynq -o $@

# Imagen final
tmp/$(PROJECT).img: tmp/boot.bin zImage.bin initrd.bin tmp/$(PROJECT).tree/devicetree.dtb
	scripts/image.sh $(PROJECT)
```

### 9.3 Targets de Limpieza

```makefile
clean:
	rm -rf tmp/$(PROJECT) tmp/$(PROJECT).*

clean-cores:
	rm -rf tmp/cores

clean-all: clean clean-cores
	rm -rf tmp/
```

---

## 10. Compilación Paso a Paso

### 10.1 Prerequisitos

```bash
# Instalar toolchain ARM
sudo apt install gcc-arm-linux-gnueabihf

# Instalar Vivado (incluye Bootgen y XSCT)
# https://www.xilinx.com/support/download.html

# Configurar entorno
source /opt/Xilinx/Vivado/2024.1/settings64.sh
```

### 10.2 Construir el Proyecto

```bash
# Clonar repositorio
git clone https://github.com/user/red-pitaya-dev.git
cd red-pitaya-dev

# Seleccionar proyecto
export PROJECT=multi_trigger_adc

# Empaquetar IP cores
make cores

# Crear proyecto Vivado (abre GUI para inspección)
make tmp/$PROJECT.xpr
vivado tmp/$PROJECT.xpr

# Generar bitstream
make tmp/$PROJECT.bit

# Generar imagen booteable
make tmp/$PROJECT.img
```

### 10.3 Actualización Parcial

Después de modificar solo el RTL:

```bash
# Re-empaquetar el core modificado
make tmp/cores/axis_trigger

# Re-sintetizar (Vivado detecta el cambio)
make tmp/$PROJECT.bit
```

Después de modificar solo el Device Tree:

```bash
# Regenerar DTB sin recompilar bitstream
make tmp/$PROJECT.tree/devicetree.dtb
make tmp/boot.bin
```

---

## 11. Relación con el Proceso de Boteo

El proceso de construcción genera los artefactos que el Zynq consume durante el boot (ver *Booting_RedPitaya.md*):

| Artefacto | Generado por | Consumido por | Momento |
|-----------|--------------|---------------|---------|
| `BOOT.BIN` | Bootgen | BootROM | Power-on |
| `fsbl.elf` | XSCT | Contenido en BOOT.BIN | Stage 1 |
| `system.bit` | Vivado | FSBL (DevC) | Stage 1 |
| `u-boot.elf` | Cross-compile | FSBL → DDR | Stage 1→2 |
| `uImage` | Cross-compile | U-Boot | Stage 2 |
| `devicetree.dtb` | dtc | U-Boot → Kernel | Stage 2→3 |
| `initrd.bin` | cpio+gzip | U-Boot → Kernel | Stage 2→3 |

```
                    CONSTRUCCIÓN                              BOOT
┌─────────────────────────────────┐         ┌──────────────────────────────┐
│                                 │         │                              │
│  Vivado                         │         │  BootROM                     │
│    └── system.bit ──────────────┼────────►│    └── carga FSBL a OCM      │
│                                 │         │                              │
│  XSCT                           │         │  FSBL                        │
│    └── fsbl.elf ────────────────┼────────►│    ├── programa PL (bit)     │
│                                 │         │    └── carga U-Boot a DDR   │
│  Bootgen                        │         │                              │
│    └── BOOT.BIN ────────────────┼────────►│  U-Boot                      │
│                                 │         │    ├── lee uImage de FAT32  │
│  Cross-compile                  │         │    ├── lee DTB de FAT32     │
│    ├── u-boot.elf ──────────────┼────────►│    └── bootm                │
│    └── uImage ──────────────────┼────────►│                              │
│                                 │         │  Kernel                      │
│  dtc                            │         │    ├── monta initrd         │
│    └── devicetree.dtb ──────────┼────────►│    └── pivot_root a rootfs  │
│                                 │         │                              │
└─────────────────────────────────┘         └──────────────────────────────┘
```

---

## Referencias

[1]: The Zynq Book – *Embedded Processing with the ARM Cortex-A9*, Caps. 14-15: Vivado IP Integrator.
[2]: Xilinx UG1118 – [Vivado Design Suite User Guide: Creating and Packaging Custom IP](https://docs.amd.com/r/en-US/ug1118-vivado-creating-packaging-custom-ip).
[3]: Xilinx UG994 – [Vivado Design Suite User Guide: Designing IP Subsystems Using IP Integrator](https://docs.amd.com/r/en-US/ug994-vivado-ip-subsystems).
[4]: Pavel Demin – [Red Pitaya Notes](https://github.com/pavel-demin/red-pitaya-notes).
