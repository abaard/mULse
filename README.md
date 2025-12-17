# mULse

macOS Unified Logging syslog extension

A Perl script that collects log info from the macOS Unified Logging system,
by issuing the CLI command:
   - /usr/bin/log stream --predicate '(eventMessage CONTAINS[c] " LQM:")' --style syslog --debug

and presents a more condensed form, in both time and content
  - default reporting interval is increased from 5 seconds to 5 minutes
  - data items are tightened up

Output example:
  - rssi=-60dBm noise=-96dBm snr=31 cca=2.0% txRate=144.4Mbps txFrames=5962 txFail=0 txRetrans=998 rxRate=156.0Mbps rxFrames=8630 rxRetryFrames=185 rxToss=1126
  - rssi=-59dBm noise=-96dBm snr=30 cca=2.0% txRate=144.4Mbps txFrames=5294 txFail=0 txRetrans=470 rxRate=173.3Mbps rxFrames=6804 rxRetryFrames=173 rxToss=1108
  - rssi=-62dBm noise=-96dBm snr=30 cca=1.0% txRate=130.0Mbps txFrames=5285 txFail=0 txRetrans=670 rxRate=173.3Mbps rxFrames=5778 rxRetryFrames=139 rxToss=1037

## Reporting interval
A set of key indicators for wifi quality is reported every 5 minutes.
Unless a quality clause for one of the indicators is broken, e.g. CCA > 40%.
If so, the indicators are reported immediately, and the culprit is pointed out, e.g
  - [cca: 56.0>=40; self=0 other=2 ifrence=54] rssi=-58dBm noise=-96dBm snr=30 (etc)

## Configurable
You might want to adjust the quality clauses in lines 10-20 of the script.
Have a look.

It can even log to your syslog server, if you tell it: syslog=SERVERNAME

