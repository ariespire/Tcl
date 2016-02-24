
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
set k 1

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

foreach_in_collection cell $cellList {
    set cellName [get_attri $cell base_name]
    set libcellName [get_attri $cell ref_name]
    if {$libcellName == "ms00f80"} {
        continue
    }
    set downsizable [![regexp {[a-z][a-z][0-9][0-9][smf]01} $libcellName]]
    set upscable [![regexp {[a-z][a-z][0-9][0-9]s[0-9][0-9]} $libcellName]] 
	if { $downsizable == 1 } {
		set cellsensivity1 [ComputeSensitivity $cellName "downsize"]
	}
	if { $upscable == 1 } {
		set cellsensitivity2 [ComputeSensitivity $cellName "upscale"]
	}
	if { $downsizable && $upscable } {
		if { $cellsensivity1 > $cellsensivity2 } {   
    		dict set M m$k target $cellName
    		dict set M m$k change "downsize"
    		dict set M m$k sensitivity $cellsensivity1
    		incr k
    	}
		else {      
 			dict set M m$k target $cellName
    		dict set M m$k change "upscale"
    		dict set M m$k sensitivity $cellsensivity2 
    		incr k
    	}
	}
	if { $downsizable && [!$upscable] } {
		dict set M m$k target $cellName
    	dict set M m$k change "downsize"
    	dict set M m$k sensitivity $cellsensivity1
    	incr k
	}
	if { [!$downsizable] && $upscable } {
		dict set M m$k target $cellName
    	dict set M m$k change "upscale"
    	dict set M m$k sensitivity $cellsensivity2
    	incr k
	}
}

puts $M

while { [dict size $M] } {
    set maxsen 0
    set maxsencell 0
    foreach id [dict keys $M] {
        if { [dict get $M $id sensitivity] > $maxsen } {
            set maxsen [dict get $M $id sensitivity]
            set maxsencell $id
        }
    }
    set tempcellname [dict get $M $maxsencell target]
puts $tempcellname 
   set tempcell [get_cell $tempcellname ]
puts $tempcell 
   set templibcellname [get_attri $tempcell ref_name]
puts $templibcellname 
 
    if { [dict get $M $maxsencell change] == "downsize" } {
        set newlibcellname [getNextSizeDown $templibcellname]
		set tempchange downsize
puts $newlibcellname
    }
    if { [dict get $M $maxsencell change] == "upscale" } {
        set newlibcellname [getNextVtDown $templibcellname]
		set tempchange upscale
puts $newlibcellname   
 	}
 	
    size_cell $tempcell $newlibcellname
    set M [dict remove $M $maxsencell]    
    
    set newWNS [ PtWorstSlack clk ]
    if { $newWNS < 0.0 } {
        size_cell $tempcell $templibcellname
		puts $outFp "- Negslack, reverting change ..."  
  	} else {
  		if { ($tempchange == "downsize" } {
			incr SizeswapCnt
            puts $outFp "- cell ${tempcellname} is swapped to $newlibcellname"
		}
  		if { $tempchange == "upscale" } {
			incr VtswapCnt
            puts $outFp "- cell ${tempcellname} is swapped to $newlibcellname"
		}
  	}

    set downsizable [![regexp {[a-z][a-z][0-9][0-9][smf]01} $newlibcellname]]
    set upscable [![regexp {[a-z][a-z][0-9][0-9]s[0-9][0-9]} $newlibcellname]]
	if { $downsizable == 1 } {
		set cellsensivity1 [ComputeSensitivity $tempcellname "downsize"]
	}
	if { $upscable == 1 } {
		set cellsensitivity2 [ComputeSensitivity $tempcellname "upscale"]
	}
	if { $downsizable && $upscable } {
		if { $cellsensivity1 > $cellsensivity2 } {
		 	dict set M m$k target $tempcellname
    		dict set M m$k change "downsize"
    		dict set M m$k sensitivity $cellsensivity1
    		incr k
    	}
		else {
 			dict set M m$k target $tempcellname
    	dict set M m$k change "upscale"
    		dict set M m$k sensitivity $cellsensivity2
    		incr k
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
