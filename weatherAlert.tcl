#! /usr/bin/tclsh

#Set required packages
package require http 2
package require tls 1.7

#Setup https handling 
::http::register https 443 [list ::tls::socket -autoservername true]

#Good Zone for testing purposes in Summer, often heat warnings
set ZONE "AZC005" 
set SILENT 0
#Parse cmd line options
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
#Get current time to check existing alerts for expiration 
set currentTime [clock seconds]
#Make alerts dir if not present
if {![file isdirectory alerts]} {
	file mkdir alerts
}
#Check files in alerts dir for current zone and expiration
if {[llength [glob -nocomplain -directory alerts $ZONE.*]] >0} {
	set files [glob -directory alerts $ZONE.*]
	foreach _file $files {
			set fd [open $_file r]
			set filetime [read $fd]
			set cmp ""
			regexp {[0-9]+\-[0-9]+\-[0-9]+[A-Z][0-9]+:[0-9]+:[0-9]+} $filetime cmp
			set cmp [clock scan $cmp]
			#Delete if alert is expired
			if {$currentTime > $cmp} {
				file delete -force $_file
			}
	}
}
#Query NOAA for XML
http::config -useragent moop
set url "https://alerts.weather.gov/cap/wwaatmget.php?x=$ZONE&y=0"
set r [::http::geturl $url]
#Make sure we got a good response
if { [string match [::http::status $r] "ok"] && [string match [::http::ncode $r] "200"]} {
	#Check if returned invalid; if not continue
	if {![string match [::http::data $r] "? invalid county '$ZONE'"]} {
		#Split the data into a list
		set xml_o [split [::http::data $r] "\n"]
		set xml ""
		set inSection 0
		set entries_count 0
		set tmp ""
		set entries ""
		#Split up the entry sections to parse later
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
		#If we have any entries, continue
		set printed 0
		if {[dict size $entries] > 0} {
			dict for {id xml} $entries {
				set CAPs ""
				#Parse out the CAP elements, this is the warning data
				foreach itr $xml {
					if {[regexp {\<cap\:} $itr]} {
						lappend CAPs $itr
					}
				}
				#Make sure we have elements to look at
				if {[llength $CAPs] > 0} {
					#Figure out the ID from the Warning for logging
					set id ""
					regexp {<id>[a-zA-z0-9:\/?=.]+\/[a-zA-z0-9:\/?=.]+\.([0-9a-f]+)<\/id>} $xml match id
					set id $ZONE.$id
					#Extract the Summary
					set summary ""
					regexp {<summary>([A-Za-z0-9.,_\s-]+)<\/summary>} $xml match summary
					#Check and make sure we haven't reported this Alert before
					if {![file exists alerts/$id]} {
						#init storage for alert data
						set event ""
						set effective ""
						set expires ""
						set msgType ""
						set areaDesc ""
						set severity ""
						#List of elements to extract from cap
						set _info [list event effective expires msgType areaDesc severity]
						#Extract cap data
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
						#Print data to stdout
						if {[string match $areaDesc ""]} {
							set areaDesc $ZONE
						}
						puts "There is a $severity Weather $msgType for $areaDesc: $event. From $effective till $expires. $summary"
						#Set that we have new alerts
						if {!$printed} {
							set printed 1
						}
						#Log alert with expiration time
						set fd [open "alerts/$id" w]
						puts -nonewline $fd $expires
						close $fd
					}
				}
			}
			#If there are weather alerts, but none are new, report as such
			if {!$printed } {
				if {!$SILENT} {
					puts "There are no new warnings to report"
				}
			}
		} else {
			#If we are silent skip
			if {!$SILENT} {
				#If there are no alerts, inform user
				puts "There is no weather warning for $ZONE at this time"
			}
		}
	} else {
		#If not silent, alert user of invalid code
		if {!$SILENT} {
			puts "Invalid County Code"
		}
	}
#Error getting webpage	
} else {
	if {!SILENT} {
		puts "Error pulling NOAA data. Code [::http::ncode $r]"
	}
}
