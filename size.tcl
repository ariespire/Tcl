
set design [get_attri [current_design] full_name]
set outFp [open ${design}_sizing.rpt w]

set initialWNS  [ PtWorstSlack clk ]
set initialLeak [ PtLeakPower ]
set capVio [ PtGetCapVio ]
set tranVio [ PtGetTranVio ]
puts $outFp "Initial slack:\t${initialWNS} ps"
puts $outFp "Initial leakage:\t${initialLeak} W"
puts $outFp "Final $capVio"
puts $outFp "Final $tranVio"
puts $outFp "======================================" 

set cellList [get_cell *]
set VtswapCnt 0
set SizeswapCnt 0


proc ComputeSensitivity { cellName operation } {

	set cell [get_cell $cellName]
	set libcell [get_lib_cells -of_objects $cellName]
	set libcellName [get_attri $libcell base_name]
	set SlackOld [PtCellSlack $cellName]
	set LeakOld [PtCellLeak $cellName]
	set DelayOld [PtCellDelay $cellName]
	if { $operation == "downsize" } {
	    set newlibcellName [getNextSizeDown $libcellName]
	    if { $newlibcellName != "skip" } {
		size_cell $cellName $newlibcellName
		set SlackNew [PtCellSlack $cellName]
		set LeakNew [PtCellLeak $cellName]
		set DelayNew [PtCellDelay $cellName]
		set Paths [expr {[PtCellFanout $cellName]+[PtCellFanin $cellName]}]
		set Sensitivity [expr {($LeakNew-$LeakOld)*($SlackNew-$SlackOld)/$Paths}]
		size_cell $cellName $libcellName
	    }
	}
	if { $operation == "upscale" } {
	    set newlibcellName [getNextVtDown $libcellName]
	    if { $newlibcellName != "skip" } {
		size_cell $cellName $newlibcellName
		set SlackNew [PtCellSlack $cellName]
		set LeakNew [PtCellLeak $cellName]
		set DelayNew [PtCellDelay $cellName]
		set Paths [expr {[PtCellFanout $cellName]+[PtCellFanin $cellName]}]
		set Sensitivity [expr {($LeakNew-$LeakOld)*($SlackNew-$SlackOld)/$Paths}]
		size_cell $cellName $libcellName
	    }
	}
	return $Sensitivity
}


set k 1

foreach_in_collection cell $cellList {
    set cellName [get_attri $cell base_name]
    set libcellName [get_attri $cell ref_name]

    if {$libcellName == "ms00f80"} {
        continue
    }

    if { ![regexp {[a-z][a-z][0-9][0-9][smf]01} $libcellName] } {
    dict set M m$k target $cellName
    dict set M m$k change "downsize"
    dict set M m$k sensitivity [ComputeSensitivity $cellName "downsize"]
    incr k
    }
    if { ![regexp {[a-z][a-z][0-9][0-9]s[0-9][0-9]} $libcellName] } {
       dict set M m$k target $cellName
    dict set M m$k change "upscale"
    dict set M m$k sensitivity [ComputeSensitivity $cellName "upscale"]
    incr k
    }
	
    #set_user_attribute $cell CellSensitivity [dict get M sensitivity]
}

puts $M










while { [dict size $M] } {
    set maxsen 0
    set maxsencell 0
    foreach id [dict keys $M] {
        if { [dict get $M $id sensitivity] > maxsen } {
            set maxsen [dict get $M $id sensitivity]
            set maxsencell $id
        }
    }
    set tempchange downsize
    set tempcellname [dict get $M $maxsencell target]
    set tempcell [get_cell $tempcellname ]
    set templibcell [get_attri $tempcell ref_name]
    set newlibcell [getNextSizeDown $templibcell]
    if { [dict get $M $maxsencell change] == "downsize"} {
        size_cell tempcell $newlibcell
    }
    else if { [dict get $M $maxsencell change] == "upscale" } {
        set tempchange upscale
        set tempcellname [dict get $M $maxsencell target]
        set tempcell [get_cell $tempcellname ]
        set templibcell [get_attri $tempcell  ref_name]
        set newlibcell [getNextVtDown $templibcell]
        size_cell $tempcell $newlibcell
        }
    dict remove $M $maxsencell    
    set newWNS [ PtWorstSlack clk ]
    if { $newWNS < 0.0 } {
            size_cell $tempcell $templibcell
    } else  if { ![regexp {[a-z][a-z][0-9][0-9][smf]01} $newlibcell] } {
        dict set M m$k target $tempcellname
        dict set M m$k change "downsize"
        dict set M m$k sensitivity [ComputeSensitivity $tempcellname "downsize"]
        incr k
        }
        else if { ![regexp {[a-z][a-z][0-9][0-9]s[0-9][0-9]} $newlibcell] } {
           dict set M m$k target $tempcellname
        dict set M m$k change "upscale"
        dict set M m$k sensitivity [ComputeSensitivity $tempcellname "upscale"]
        incr k
        }
    }
}














#set cellListM [sort_collection -descending $cellList { CellSensitivty }]
set cellListM [sort_collection -descending $M { [dict get M sensitivity] }]
puts $cellListM

foreach_in_collection cell $cellListM {
    set cellName [get_attri $cell base_name]
    set libcell [get_lib_cells -of_objects $cellName]
    set libcellName [get_attri $libcell base_name]
    if {$libcellName == "ms00f80"} {
        continue
    }
	set CellOperation [dict get M change]
	if { $CellOperation == "downsize" } {
	    set newlibcellName [getNextSizeDown $libcellName]
	    size_cell $cellName $newlibcellName
            set newWNS [ PtWorstSlack clk ]
            if { $newWNS < 0.0 } {
                size_cell $cellName $libcellName
            } else {
                incr VtswapCnt


                puts $outFp "- cell ${cellName} is swapped to $newlibcellName"
            }
	}
	if { $CellOperation == "upscale" } {
	    set newlibcellName [getNextVtDown $libcellName]
	    size_cell $cellName $newlibcellName
            set newWNS [ PtWorstSlack clk ]
            if { $newWNS < 0.0 } {
                size_cell $cellName $libcellName
            } else {
                incr VtswapCnt


                puts $outFp "- cell ${cellName} is swapped to $newlibcellName"
            }
	}
}

set finalWNS  [ PtWorstSlack clk ]
set finalLeak [ PtLeakPower ]
set capVio [ PtGetCapVio ]
set tranVio [ PtGetTranVio ]
set improvment  [format "%.3f" [expr ( $initialLeak - $finalLeak ) / $initialLeak * 100.0]]
puts $outFp "======================================" 
puts $outFp "Final slack:\t${finalWNS} ps"
puts $outFp "Final leakage:\t${finalLeak} W"
puts $outFp "Final $capVio"
puts $outFp "Final $tranVio"
puts $outFp "#Vt cell swaps:\t${VtswapCnt}"
puts $outFp "#Cell size swaps:\t${SizeswapCnt}"
puts $outFp "Leakage improvment\t${improvment} %"

close $outFp    

