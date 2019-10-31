# TeslaClimate
Climate your Tesla using a Tcl Script.
 
Thanks to [Tim Dorr](https://tesla-api.timdorr.com) for his great work to reengeneer the Tesla-API.
 
## What it does
 
The pure Tcl script `TeslaClimate.tcl` makes a HTTPS connection to Tesla using the REST API (like the iOS or Android App), reads the list of your cars to find out the correct id of the wanted car, wakes up the car, sets up the temperature and starts up the climate progress. 

## Starting the script
 
The Tcl application can be started immediately using the tclsh. You can start the Tcl script using the "at" unix command at a specific time. The shell script `TeslaClimate.sh` shows you how to use it.

## Configuration

You can find the neccessary secrets in the configuration file `TeslaClimate.cfg`. You have to setup the variables `EMAIL`, `PASSWORD` and `NAME` (the name of your car). `TEMP` is the temperature you want to set. The password must be crypted using the rc4 Tcl package with the key "void" like this:

~~~tcl
package require rc4
puts [rc4::rc4 -hex -key "void" "top secret"]
~~~
