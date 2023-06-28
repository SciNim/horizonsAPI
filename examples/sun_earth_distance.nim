import ../horizonsapi
import std / [asyncdispatch, strutils] 
# let's try a simple request
let comOpt = { #coFormat : "json", # data returned as "fake" JSON 
               coMakeEphem : "YES", 
               coCommand : "10",  # our target is the Sun, index 10
               coEphemType : "OBSERVER" }.toTable # observational parameters
let ephOpt = { eoCenter : "coord@399", # observational point is a coordinate on Earth (Earth idx 399)
               eoStartTime : "2022-01-01", 
               eoStopTime : "2022-12-31",
               eoStepSize : "1 HOURS", # in 1 hour steps
               eoCoordType : "GEODETIC", 
               eoSiteCoord : "+0.0,+51.477806,0", # Greenwich coordinates, because why not?
                                                  # First East/West than North/South! Last field is altitude
               eoCSVFormat : "YES" }.toTable # data as CSV within the JSON (yes, really)
var q: Quantities
q.incl 20 ## Observer range! In this case range between our coordinates on Earth and target

let fut = request(comOpt, ephOpt, q) # construct the request & perform it async
## If multiple we would `poll`! 
let res = fut.waitFor() # wait for it

let resJ = res.parseJson# result is json, so can parse it
for l in resJ["result"].getStr.splitLines()[0 .. 30]:
  echo l

## Or alternatively: Construct a HorizonsRequest object and use `getResponses`, which
## takes a `seq` of requests and processes them concurrently. The result is a
## `seq[HorizonsResponse]`, which has seen very basic parsing. The data is split
## into a header, footer and a data section. The data section (if `eoCSVFormat` is
## set to 'YES') can be parsed e.g. with datamancer's `parseCsvString`
import datamancer
block Alt:  
  let req = initHorizonsRequest(comOpt, ephOpt, q)
  let res = getResponses(@[req])
  let df = parseCsvString(res[0].csvData)
  echo df
