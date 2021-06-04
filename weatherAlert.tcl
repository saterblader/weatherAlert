#! /usr/bin/tclsh

package require http 2
package require tls 1.7

::http::register https 443 [list ::tls::socket -autoservername true]

set ZONE "AZC005"
set SILENT 0
foreach {arg param} $argv {
	if { [string match -nocase $arg "-zone"]} {
		set ZONE $param
	} elseif {[string match -nocase $arg "-silent"]} {
		if {[string match -nocase $param "on"]} { 
			set SILENT 1
		}
	} else {
		puts "Invalid Argument - Program Terminates"
		exit 1
	}
}

set currentTime [clock seconds]
if {![file isdirectory alerts]} {
	file mkdir alerts
}
if {[llength [glob -nocomplain -directory alerts $ZONE.*]] >0} {
set files [glob -directory alerts $ZONE.*]
foreach _file $files {
	puts $_file
	set fd [open $_file r]
	set filetime [read $fd]
	set cmp ""
	regexp {[0-9]+\-[0-9]+\-[0-9]+[A-Z][0-9]+:[0-9]+:[0-9]+} $filetime cmp
	set cmp [clock scan $cmp]
	if {$currentTime > $cmp} {
		file delete $_file
	}
}
}

http::config -useragent moop
set url "https://alerts.weather.gov/cap/wwaatmget.php?x=$ZONE&y=0"
set r [::http::geturl $url]
if { [string match [::http::status $r] "ok"] && [string match [::http::ncode $r] "200"]} {
set xml_o [split [::http::data $r] "\n"]
set xml ""
set inSection 0
set entries_count 0
set tmp ""
set entries ""
foreach line $xml_o {
	if {[string match $line "<entry>"]} {
		set inSection 1
		incr entries_count
		set tmp ""
	}
	if {$inSection} {
		lappend tmp $line
	}
	if {[string match $line "<\/entry>"]} {
		set inSection 0
		dict set entries $entries_count $tmp
	}
}
if {[dict size $entries] > 0} {
dict for {$id xml} $entries {
set CAPs ""
foreach itr $xml {
	if {[regexp {\<cap\:} $itr]} {
		lappend CAPs $itr
	}
}
if {[llength $CAPs] > 0} {
set id ""
regexp {<id>[a-zA-z0-9:\/?=.]+\/[a-zA-z0-9:\/?=.]+\.([0-9a-f]+)<\/id>} $xml match id
set id $ZONE.$id
set summary ""
regexp {<summary>([A-Za-z0-9.,_\s-]+)<\/summary>} $xml match summary
if {![file exists alerts/$id]} {
set event ""
set effective ""
set expires ""
set msgType ""
set areaDesc ""
set severity ""
set _info [list event effective expires msgType areaDesc severity]
foreach itr $_info {
	set value ""
	set exp "<cap:$itr>(\[A-Za-z0-9\\s:-\]+)<\/cap:$itr>"
	foreach itx $CAPs {
		set status [regexp $exp $itx match value]
		#puts $status
		if {$status} {
			set $itr $value
		}
		
	}
}
puts "There is a $severity Weather $msgType for $areaDesc: $event. From $effective\
till $expires. $summary"
set fd [open "alerts/$id" w]
puts -nonewline $fd $expires
close $fd
}
}
}
} else {
	if {!$SILENT} {
		puts "There is no weather warning for $ZONE at this time"
	}
}
}
