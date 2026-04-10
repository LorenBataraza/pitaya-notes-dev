set project_name [lindex $argv 0]
open_project tmp/${project_name}.xpr
open_bd_design [get_files *.bd]
write_bd_tcl -force projects/${project_name}/block_design_exported.tcl
close_project
