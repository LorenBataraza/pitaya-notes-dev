## @file    core_sv.tcl
## @brief   Package a SystemVerilog module as a Vivado IP core.
## @details Accepts a source path, a stem used as project and IP name,
##          and the target FPGA part. Produces a packaged IP under
##          tmp/cores/dev/<stem>. SystemVerilog packages matching
##          rtl/**/*_pkg.sv are added as elaboration support files.
##
## @param argv[0]  Path to the .sv source file (e.g. rtl/common/foo.sv)
## @param argv[1]  Project stem, subdirectory-relative (e.g. rtl/common/foo)
## @param argv[2]  Xilinx part string (e.g. xc7z010clg400-1)

set src_file  [lindex $argv 0]
set core_stem [lindex $argv 1]
set part_name [lindex $argv 2]

set core_name [file tail $core_stem]
set core_dir  tmp/cores/dev/$core_stem

file delete -force $core_dir \
    ${core_dir}.cache ${core_dir}.hw \
    ${core_dir}.ip_user_files ${core_dir}.sim ${core_dir}.xpr

create_project -part $part_name $core_name $core_dir

add_files -norecurse $src_file

set pkg_files [glob -nocomplain rtl/*_pkg.sv rtl/**/*_pkg.sv]
if {[llength $pkg_files] > 0} {
    add_files -norecurse $pkg_files
}

set_property TOP $core_name [current_fileset]

ipx::package_project -root_dir $core_dir

set core [ipx::current_core]

set_property VERSION             {1.0}                $core
set_property NAME                $core_name           $core
set_property LIBRARY             {user}               $core
set_property VENDOR              {balseiro}           $core
set_property VENDOR_DISPLAY_NAME {Instituto Balseiro} $core
set_property SUPPORTED_FAMILIES  {zynq Production}    $core

ipx::create_xgui_files $core
ipx::update_checksums  $core
ipx::save_core         $core

close_project
