import std / [strutils, strformat, httpclient, asyncdispatch, sequtils, parseutils, os, json, tables, uri]
const basePath = "https://ssd.jpl.nasa.gov/api/horizons.api?"
const outPath = currentSourcePath().parentDir.parentDir / "resources/"

export tables, json

when not defined(ssl):
  {.error: "This module must be compiled with `-d:ssl`.".}

## See the Horizons manual for a deeper understanding of all parameters:
## https://ssd.jpl.nasa.gov/horizons/manual.html
## And the API reference:
## https://ssd-api.jpl.nasa.gov/doc/horizons.html
type
  CommonOptionsKind* = enum
    coFormat = "format"        ## 'json', 'text'
    coCommand = "COMMAND"      ## defines the target body! '10' = Sun, 'MB' to get a list of available targets
    coObjData = "OBJ_DATA"     ## 'YES', 'NO'
    coMakeEphem = "MAKE_EPHEM" ## 'YES', 'NO'
    coEphemType = "EPHEM_TYPE" ## 'OBSERVER', 'VECTORS', 'ELEMENTS', 'SPK', 'APPROACH'
    coEmailAddr = "EMAIL_ADDR"

  ## Available for 'O' = 'OBSERVER', 'V' = 'VECTOR', 'E' = 'ELEMENTS'
  EphemerisOptionsKind* = enum                    ##  O       V       E
    eoCenter = "CENTER"                          ##  x       x       x    'coord@399' = coordinate from `SiteCoord' on earth (399)
    eoRefPlane = "REF_PLANE"                     ##          x       x
    eoCoordType = "COORD_TYPE"                   ##  x       x       x    'GEODETIC', 'CYLINDRICAL'
    eoSiteCoord = "SITE_COORD"                   ##  x       x       x    if GEODETIC: 'E-long, lat, h': e.g. Geneva: '+6.06670,+46.23330,0'
    eoStartTime = "START_TIME"                   ##  x       x       x    Date as 'YYYY-MM-dd'
    eoStopTime = "STOP_TIME"                     ##  x       x       x
    eoStepSize = "STEP_SIZE"                     ##  x       x       x    '60 min', '1 HOURS', ...
    eoTList = "TLIST"                            ##  x       x       x
    eoTListType = "TLIST_TYPE"                   ##  x       x       x
    eoQuantities = "QUANTITIES"                  ##  x                    !!! These are the data fields you want to get !!!
    eoRefSystem = "REF_SYSTEM"                   ##  x       x       x
    eoOutUnits = "OUT_UNITS "                    ##          x       x    'KM-S', 'AU-D', 'KM-D' (length & time, D = days)
    eoVecTable = "VEC_TABLE "                    ##          x
    eoVecCorr = "VEC_CORR "                      ##          x
    eoCalFormat = "CAL_FORMAT"                   ##  x
    eoCalType = "CAL_TYPE"                       ##  x       x       x
    eoAngFormat = "ANG_FORMAT"                   ##  x
    eoApparent = "APPARENT"                      ##  x
    eoTimeDigits = "TIME_DIGITS"                 ##  x       x       x
    eoTimeZone = "TIME_ZONE"                     ##  x
    eoRangeUnits = "RANGE_UNITS"                 ##  x                    'AU', 'KM'
    eoSuppressRangeRate = "SUPPRESS_RANGE_RATE"  ##  x
    eoElevCut = "ELEV_CUT"                       ##  x
    eoSkipDayLT = "SKIP_DAYLT"                   ##  x
    eoSolarELong = "SOLAR_ELONG"                 ##  x
    eoAirmass = "AIRMASS"                        ##  x
    eoLHACutoff = "LHA_CUTOFF"                   ##  x
    eoAngRateCutoff = "ANG_RATE_CUTOFF"          ##  x
    eoExtraPrec = "EXTRA_PREC"                   ##  x
    eoCSVFormat = "CSV_FORMAT"                   ##  x       x       x
    eoVecLabels = "VEC_LABELS"                   ##          x
    eoVecDeltaT = "VEC_DELTA_T"                  ##          x
    eoELMLabels = "ELM_LABELS "                  ##                  x
    eoTPType = "TP_TYPE"                         ##                  x
    eoRTSOnly = "R_T_S_ONLY"                     ##  x

  Quantities* = set[1 .. 48]
    ##    1. Astrometric RA & DEC
    ##  * 2. Apparent RA & DEC
    ##    3.   Rates; RA & DEC
    ## ,* 4. Apparent AZ & EL
    ##    5.   Rates; AZ & EL
    ##    6. Satellite X & Y, position angle
    ##    7. Local apparent sidereal time
    ##    8. Airmass and Visual Magnitude Extinction
    ##    9. Visual magnitude & surface Brightness
    ##   10. Illuminated fraction
    ##   11. Defect of illumination
    ##   12. Satellite angle of separation/visibility code
    ##   13. Target angular diameter
    ##   14. Observer sub-longitude & sub-latitude
    ##   15. Sun sub-longitude & sub-latitude
    ##   16. Sub-Sun position angle & distance from disc center
    ##   17. North pole position angle & sistance from disc center
    ##   18. Heliocentric ecliptic longitude & latitude
    ##   19. Heliocentric range & range-rate
    ##   20. Observer range & range-rate
    ##   21. One-way down-leg light-time
    ##   22. Speed of target with respect to Sun & observer
    ##   23. Sun-Observer-Targ ELONGATION angle
    ##   24. Sun-Target-Observer ~PHASE angle
    ##   25. Target-Observer-Moon/Illumination%
    ##   26. Observer-Primary-Target angle
    ##   27. Position Angles; radius & -velocity
    ##   28. Orbit plane angle
    ##   29. Constellation Name
    ##   30. Delta-T (TDB - UT)
    ##,* 31. Observer-centered Earth ecliptic longitude & latitude
    ##   32. North pole RA & DEC
    ##   33. Galactic longitude and latitude
    ##   34. Local apparent SOLAR time
    ##   35. Earth->Site light-time
    ## > 36. RA & DEC uncertainty
    ## > 37. Plane-of-sky (POS) error ellipse
    ## > 38. Plane-of-sky (POS) uncertainty (RSS)
    ## > 39. Range & range-rate sigma
    ## > 40. Doppler/delay sigmas
    ##   41. True anomaly angle
    ##,* 42. Local apparent hour angle
    ##   43. PHASE angle & bisector
    ##   44. Apparent target-centered longitude of Sun (L_s)
    ##,* 45. Inertial frame apparent RA & DEC
    ##   46.   Rates: Inertial RA & DEC
    ##,* 47. Sky motion: angular rate & angles
    ##   48. Lunar sky brightness & target visual SNR

  CommonOptions* = Table[CommonOptionsKind, string]
  EphemerisOptions* = Table[EphemerisOptionsKind, string]

  HorizonsResponse* = object
    header*: string
    footer*: string
    csvData*: string # <- the data field can be parsed using `parseCsvString` from `datamancer`

  HorizonsRequest* = object
    commonOpt*: CommonOptions
    ephemerisOpt*: EphemerisOptions
    quantities*: Quantities

## Example URL:
## https://ssd.jpl.nasa.gov/api/horizons.api?format=text&COMMAND='499'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='500@399'&START_TIME='2006-01-01'&STOP_TIME='2006-01-20'&STEP_SIZE='1%20d'&QUANTITIES='1,9,20,23,24,29'
proc serialize*[T: CommonOptions | EphemerisOptions](opts: T): string =
  # turn into seq[(string, string)] and encase values in `'`
  let opts = toSeq(opts.pairs).mapIt(($it[0], &"'{it[1]}'"))
  result = opts.encodeQuery()

proc serialize*(q: Quantities): string =
  result = "QUANTITIES='"
  var i = 0
  for x in q:
    result.add &"{x}"
    if i < q.card - 1:
      result.add ","
    inc i
  result.add "'"

proc request*(cOpt: CommonOptions, eOpt: EphemerisOptions, q: Quantities): Future[string] {.async.} =
  var req = basePath
  req.add serialize(cOpt) & "&"
  req.add serialize(eOpt) & "&"
  req.add serialize(q)
  echo "Performing request to: ", req
  var client = newAsyncHttpClient()
  return await client.getContent(req)

proc initHorizonsRequest*(cOpt: CommonOptions, eOpt: EphemerisOptions, q: Quantities): HorizonsRequest =
  result = HorizonsRequest(commonOpt: cOpt, ephemerisOpt: eOpt, quantities: q)

proc parseHorizonsResponse*(response: string): HorizonsResponse =
  ## Parses the given string of the Horizons response and returns it as
  ## an object with header, footer and data body separated.
  let res = response.parseJson["result"].getStr #.multireplace((r"\n", "FOO"))
  const Start = "$$SOE"
  const End = "$$EOE"
  const DataHeader = "Table format"
  # let's keep the parsing simple
  let dataStartIdx = res.find(Start) # indicates start of data
  let dataEndIdx = res.find(End)
  if dataStartIdx < 0:
    echo "ERROR:\n\n"
    echo res
  let header = res[0 ..< dataStartIdx]
  let dataHeaderTab = header.find(DataHeader)
  const DataHeaderStart = "*\n" ## NOTE: after `Table format`!
  const DataHeaderStop = ",\n" ## NOTE: after `DataHeaderStart`!
  let dataHeaderStart = header.find(DataHeaderStart, start = dataHeaderTab)
  let dataHeaderStop = header.find(DataHeaderStop, start = dataHeaderStart)
  let dataHeader = header[dataHeaderStart + DataHeaderStart.len .. dataHeaderStop].strip
  let data = res[dataStartIdx + Start.len ..< dataEndIdx].strip
  result = HorizonsResponse(header: header.strip,
                            footer: res[dataEndIdx + End.len .. ^1].strip,
                            csvData: dataHeader & "\n" & data)

proc getResponses*(reqs: seq[HorizonsRequest]): seq[HorizonsResponse] =
  var futs = newSeq[Future[string]](reqs.len)
  for i, r in reqs:
    futs[i] = request(r.commonOpt, r.ephemerisOpt, r.quantities)
  while futs.anyIt(not it.finished()):
    poll()
  result = newSeq[HorizonsResponse](reqs.len)
  for i, f in futs:
    result[i] = parseHorizonsResponse(waitFor(f))

proc getResponsesSync*(reqs: seq[HorizonsRequest]): seq[HorizonsResponse] =
  ## Non-async version of `getResponses`. I think the server does not like the async version
  var res = newSeq[string](reqs.len)
  for i, r in reqs:
    res[i] = waitFor request(r.commonOpt, r.ephemerisOpt, r.quantities)
  result = newSeq[HorizonsResponse](res.len)
  for i, r in res:
    result[i] = parseHorizonsResponse(r)

when isMainModule:
  # let's try a simple request
  let comOpt = { #coFormat : "text",
                 coMakeEphem : "YES",
                 coCommand : "10",
                 coEphemType : "OBSERVER" }.toTable
  let ephOpt = { eoCenter : "coord@399",
                 eoStartTime : "2017-01-01",
                 eoStopTime : "2017-12-31",
                 eoStepSize : "1 DAYS",
                 eoCoordType : "GEODETIC",
                 eoSiteCoord : "+6.06670,+46.23330,0",
                 eoCSVFormat : "YES" }.toTable
  var q: Quantities
  q.incl 20 ## Observer range!

  let req = initHorizonsRequest(comOpt, ephOpt, q)
  let res = getResponses(@[req])

  echo res
  import datamancer
  let df = parseCsvString(res[0].csvData)
  echo df

  when false:
    let fut = request(comOpt, ephOpt, q)
    ## If multiple we would `poll`!
    let res = fut.waitFor()

    echo res.parseJson.pretty()
