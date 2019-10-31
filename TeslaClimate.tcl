###############################################################################
#
# @file
# @brief Zeitgesteuerte Vorklimatisierung eines Teslas
# @mainpage
# @author Jörg Mehring
# @version 0.1
#
# Programm, um einen Tesla mit Hilfe des Tesla JSON API von Tim Dorr per Skript
# vorzuklimatisieren. Das Programm weckt, falls nötig, den Wagen auf, lädt die
# aktuellen Temperaturwerte und schaltet dann die Klimatisierung auf den in der
# Konfigurationsdatei angegebenen Temperaturwert. Somit kann über ein at-Skript
# die Heizung oder Kühlung eingeschaltet werden, ohne dass man das Smartphone
# bemühen müsste.
#
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

proc Log {str} {
  set t [clock milliseconds]
  set m [expr {$t % 1000}]
  set s [expr {$t / 1000}]
  puts [format "%s.%03u %s" [clock format $s -format {%Y-%m-%d %H:%M:%S}] $m $str]
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

proc json2dict {json} {
  return [json::json2dict $json]
}


proc str2json {value} {
  switch -- $value {
    "" - null {
      # value is json null value
      set value null
    }
    true - yes {
      # value is json boolean true
      set value true
    }
    false - no {
      # value is json boolean false
      set value false
    }
    default {
      if {[string index $value 0] == "\[" && [string index $value end] == "\]"} {
	      # value is json array
      } elseif {[string index $value 0] == "\{" && [string index $value end] == "\}"} {
	      # value is json struct
      } else {
	      if {[string is double -strict $value]} {
	        # value is json number
	      } else {
	        set value \"$value\"
	      }
      }
    }
  }
  return $value
}


proc dict2json {dvals} {
  set result ""
  foreach {name value} $dvals {
    if {$result ne ""} {
      append result ","
    }
    append result \"$name\":[str2json $value]
  }
  return "{$result}"
}


proc list2json {lvals} {
  set result ""
  foreach value $lvals {
    if {$result ne ""} {
      append result ","
    }
    if {[string index $value 0] == "\{"} {
      append result $value
    } else {
      append result [str2json $value]
    }
  }
  return "\[$result\]"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

proc dget {dict item {default ""}} {
  if {[dict exists $dict $item]} {
    return [dict get $dict $item]
  }
  return $default
}


proc dprint {dict} {
  set max_len 0 
  catch {
    dict for {item value} $dict {
      set max_len [expr max([string length $item], $max_len)]
    }
    dict for {item value} $dict {
      Log [format "%-*s = %s" $max_len $item $value]
    }
  }
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

proc Init {} {
  global oauth_token oauth_expiry refresh_token headers
  
  package require http
  set ::http::defaultCharset utf-8
  package require json
  package require rc4
  package require tls
  tls::init -tls1 1
  http::register https 443 ::tls::socket

  set headers [dict create User-Agent "TeslaClimateClient/0.1"]
  
  uplevel #0 { source TeslaClimate.cfg }

  set oauth_token {}
  set oauth_expiry 0
  set refresh_token {}
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

proc OAuth {} {
  global URL TESLA_CLIENT_ID TESLA_CLIENT_SECRET EMAIL PASSWORD
  global oauth_token oauth_expiry headers
  
  set now [clock seconds]
  if {$oauth_token eq {}} {
    if {[file readable TeslaClimate.oauth]} {
      source TeslaClimate.oauth
    }
  }
  if {$oauth_token eq {} || $now > $oauth_expiry} {
    set queryData [dict create]
    dict set queryData grant_type    password
    dict set queryData client_id     $TESLA_CLIENT_ID
    dict set queryData client_secret $TESLA_CLIENT_SECRET
    dict set queryData email         $EMAIL
    dict set queryData password      [rc4::rc4 -key void [binary format H* $PASSWORD]]

    set url     $URL/oauth/token
    set query   [http::formatQuery {*}$queryData]
    set token   [http::geturl $url -headers $headers -query $query -timeout 120000]
    set status  [http::status $token]
    if {$status eq "ok"} {
      set jsonData [http::data $token]
      if {$jsonData ne {}} {
        set resultDict [json::json2dict $jsonData]
        # Log "resultDict = $resultDict"
        if {[dict exists $resultDict access_token]} {
          set oauth_token   [dict get $resultDict access_token]
          set expires_in    [dict get $resultDict expires_in]
          set created_at    [dict get $resultDict created_at]
          set refresh_token [dict get $resultDict refresh_token]
          set oauth_expiry  [expr {$created_at + $expires_in}]
        }
      }
    }
    http::cleanup $token
    
    if {$oauth_token ne {}} {
      set fd [open TeslaClimate.oauth w]
      puts $fd [list set oauth_token $oauth_token]
      puts $fd [list set oauth_expiry $oauth_expiry]
      puts $fd [list set refresh_token $refresh_token]
      close $fd
    }
  }
  if {$oauth_token ne {}} {
    Log "Access-Token ok"
    dict set headers Authorization "Bearer $oauth_token"
    return true
  }
  Log "Access-Token nicht vorhanden"
  return false
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

proc SendPostRequest {uri {queryData {}}} {
  global URL headers
  
  Log [string repeat "-" 80]
  set url $URL$uri
  Log "url = $url"
  set query [http::formatQuery {*}$queryData]
  set token [http::geturl $url -method POST -headers $headers -query $query -timeout 120000]
  set status  [http::status $token]
  Log "status = $status"
  set resultDict {}
  if {$status eq "ok"} {
    set jsonData [http::data $token]
    if {$jsonData ne {}} {
      set resultDict [json::json2dict $jsonData]
      # Log "resultDict = $resultDict"
    }
  }
  http::cleanup $token
  return $resultDict
}


proc SendGetRequest {uri} {
  global URL headers
  
  Log [string repeat "-" 80]
  set url $URL$uri
  Log "url = $url"
  set token [http::geturl $url -method GET -headers $headers -timeout 120000]
  set status  [http::status $token]
  Log "status = $status"
  set resultDict {}
  if {$status eq "ok"} {
    set jsonData [http::data $token]
    if {$jsonData ne {}} {
      set resultDict [json::json2dict $jsonData]
      # Log "resultDict = $resultDict"
    }
  }
  http::cleanup $token
  return $resultDict
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

proc GetArgs {} {
  global argc argv argv0 opt

  array set opt {
    quick_run false
    dry_run false
  }
  for {set argi 0} {$argi < $argc} {incr argi} {
    set arg [lindex $argv $argi]
    switch -glob -- $arg {
      -h - --help {
        puts "usage: $argv0 \[<options>\]"
	puts " -h, --help    show this help"
	puts " -q, --quick   quick run (shows vehicle data only)"
	puts " -d, --dry     dry run (shows climate data only, wakeup if neccessary)"
	exit 0
      }
      -q - --quick {
        set opt(quick_run) true
      }
      -d - --dry {
        set opt(dry_run) true
      }
      -- {
        # ignore
      }
      -* {
        puts stderr "unknown option $arg"
      }
    }
  }
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

proc DoClimate {} {
  global opt NAME WAKEUP_DELAY TEMP

  Log ">>> climate start"
  # load OAuth from file or from server:
  if {[OAuth]} {
    # get list of vehicles:
    set data [SendGetRequest /api/1/vehicles]
    set vcnt [dget $data count 0]
    set vlist [dget $data response]
    # for all vehicles in list:
    for {set vidx 0} {$vidx < $vcnt} {incr vidx} {
      # load record of this vehicle:
      set vrec [lindex $vlist $vidx]
      # is this vehicle which I want to climate?
      if {[dget $vrec display_name] eq $NAME} {
	dprint $vrec

	if {$opt(quick_run)} {
	  Log ">>> terminating due to quick run"
	  return
	}

	# get id and state of this vehicle:
	set vid   [dget $vrec id]
	set state [dget $vrec state]

	set count 0
	while {$state eq "offline" && $count < 30} {
	  Log ">>> car is offline, wait a minute ..."
	  after 60000
	  
	  # read state of this vehicle again:
	  set data [SendGetRequest /api/1/vehicles/$vid]
	  Log "data = $data"
	  set vrec [dget $data response]
	  dprint $vrec

	  # get the state:
	  set state [dget $vrec state]
	  incr count
	}
	if {$count == 30} {
	  Log ">>> climate canceled because of connect errors"
	  return
	}

	# wakeup vehicle if neccessary:
	while {$state eq "asleep"} {
	  set data [SendPostRequest /api/1/vehicles/$vid/wake_up]
	  Log "data = $data"
	  set crec [dget $data response]
	  # dprint $crec
	  
	  Log ">>> waiting $WAKEUP_DELAY ms ..."
	  after $WAKEUP_DELAY
	  
	  # read state of this vehicle again:
	  set data [SendGetRequest /api/1/vehicles/$vid]
	  Log "data = $data"
	  set vrec [dget $data response]
	  dprint $vrec

	  # get the state:
	  set state [dget $vrec state]
	}

	# set data [SendGetRequest /api/1/vehicles/$vid/vehicle_data]
	# # Log "data = $data"
	# set vrec [dget $data response]
	# dprint $vrec
	
	# read the climate state:
	set data [SendGetRequest /api/1/vehicles/$vid/data_request/climate_state]
	Log "data = $data"
	set crec [dget $data response]
	dprint $crec
	
	if {$opt(dry_run)} {
	  Log ">>> terminating due to dry run"
	  return
	}

	# check, if climate is already on:
	set is_climate_on [dget $crec is_climate_on false]
	if {$is_climate_on} {
	  Log ">>> climate is already on"
	} else {
	  # read temperatures:
	  set inside_temp  [dget $crec inside_temp 0]
	  set outside_temp [dget $crec outside_temp 0]
	  set driver_temp  [dget $crec driver_temp_setting 0]

	  # it's cold outside and actual temperature is lower than set temperature
	  if {$outside_temp < 15.0 && $inside_temp < $driver_temp} {
	    # set heating temperature:
	    set params [dict create driver_temp $TEMP passenger_temp $TEMP]
	    set data [SendPostRequest /api/1/vehicles/$vid/command/set_temps $params]
	    Log "data = $data"
	    set crec [dget $data response]
	    # dprint $crec
	    if {[dget $crec result] eq "true"} {
	      Log ">>> temperature set to $TEMP °C"
	    }

	    # switch heating on:
	    set data [SendPostRequest /api/1/vehicles/$vid/command/auto_conditioning_start {}]
	    Log "data = $data"
	    set crec [dget $data response]
	    # dprint $crec
	    if {[dget $crec result]} {
	      Log ">>> climate started"
	    }

	    # read climate state again to show the differences:
	    set data [SendGetRequest /api/1/vehicles/$vid/data_request/climate_state]
	    # Log "data = $data"
	    set crec [dget $data response]
	    dprint $crec
	  } else {
	    Log ">>> not necessary to climate"
	  }
	}
	break
      }
    }
    Log ">>> climate finished"
  } else {
    Log ">>> climate error, no authorization"
  }
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

GetArgs
Init
DoClimate
