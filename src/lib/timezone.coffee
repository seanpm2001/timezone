# Some local times do not exist, like when clocks are set forward for daylight
# savings time.
#
#### Before You Can Read This Code
#
# The `wallclock` variable mentioned throughout the code is always a seconds
# since the epoch offset, but it is *not* UTC seconds since the epoch. When you
# see a `posix` variable, that is always POSIX time, seconds since the epoch,
# always UTC.
# 
# When you see a `date` variable we're using a `Date` object for its its
# `getUTC*` fields.  We use a `Date` object as a date/time record, and the
# `Date` object's `getUTC*` methods as date/time fields. We use this structure
# as a time record, but the `getUTC*` values are always going represent values
# in the user specified time zone, the `wallclock` time. This time could be UTC,
# but only if that is what the user wants.
#
# Why do we do this? Because `Date` is a built-in and compact representation of
# date and time. The `Date` object has some nice properties that makes it easy
# to do date math at the year, month and day level. It can calculate the day of
# the year. It knows how to calculate the day of the week. It knows about leap
# years.
#
# Why don't we use `get*` instead of `getUTC*`? The `get*` methods return the
# time adjusted by the current zone offset of the host machine. This zone offset
# cannot be set programatically. (If that were the case, this library would
# be happily based on the `Date` object.) The `get*` methods are not useful to
# us because they are adjusted only a zone offset, one that we cannot set, not
# by the rules of a time zone, which accounts for daylight savings time and the
# whims of the polity.
#
# That `Date` is broken is the premise of this library, yet `Date` is a little
# workhouse throughout it. 
#
#### Also Know That
#
# The `wallclock` seconds since the epoch value does not leak out to the user.
# The user will only ever get either UTC seconds since the epoch, or a formatted
# date string in the user specified time zone.
#
# When you see `posix` in the code, we've converted the `wallclock` to UTC to
# perform math at the hours, minutes, seconds, and milliscond level. We convert
# the time `wallclock` to UTC to perform the math, and then convert back into
# the `wallclock` into the user specified time zone. Thus, daylight savings time
# shifts are not lost.

# Wrap everything in a function and pass in an exports map appropriate for node
# or the browser, depending on where we are.
do -> (exports = if typeof module isnt "undefined" then module.exports else window) and do (exports) ->
  # Used for debugging. If you don't see them called in the code, it means the
  # code is absolutely bug free.
  die = (splat...) ->
    console.log.apply console, splat if splat.length
    process.exit 1
  say = (splat...) -> console.log.apply console, splat

  # Locales and time zones are global, because they are, literally, global.
  #
  # We provide UTC.
  # 
  # We provide a default locale for the United States. Currently, locales are
  # simply JSON structures, but in the future they may contain logic for locale
  # specific fuzzy date parsing.
  UTC = [ { "offset": "0", "format": "UTC" } ]
  UTC.name = "UTC"
  en_US =
    name: "en_US"
    day:
      abbrev: "Sun Mon Tue Wed Thu Fri Sat".split /\s/
      full: """
        Sunday Monday Tuesday Wednesday Thursday Friday Saturday
      """.split /\s+/
    month:
      abbrev: "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split /\s+/
      full: """
        January February March
        April   May      June
        July    August   September
        October November December
      """.split /\s+/
    dateFormat: "%m/%d/%Y"
    timeFormat: "%I:%M:%S %p"
    dateTimeFormat: "%a %d %b %Y %I:%M:%S %p %Z"
    meridiem: [ { lower: "am", upper: "AM" }, { lower: "pm", upper: "PM" } ]
    monthBeforeDate: true

  CLOCK = -> +(new Date())

  # Constants for units of time in milliseconds.
  SECOND  = 1000
  MINUTE  = SECOND * 60
  HOUR    = MINUTE * 60
  DAY     = HOUR   * 24

  ##### isLeapYear(year)

  # Return true if the given year is a leap year.
  isLeapYear = (year) ->
    if year % 400 is 0
      true
    else if year % 100 is 0
      false
    else if year % 4 is 0
      true
    else
      false

  ##### daysInMonth(month, year)

  # Return the numbers of days in the month for the given zero-indexed month in
  # the given year.
  daysInMonth = do ->
    DAYS_IN_MONTH = [ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 ]

    (month, year)->
      days = DAYS_IN_MONTH[month]
      days++ if month is 1 and isLeapYear year
      days

  ##### format(wallclock, request)
  # 
  # Formats our time `wallclock` using a UNIX date format. The `wallclock`
  # contains the field values for a valid time in the user specified time zone.
  # Invalid dates would already have been caught by `parse`.

  # We wrap up a great many helpers using an anonymous `do` function.
  format = do ->
    # The day of the year for the first day of the month for each month.
    MONTH_DAY_OF_YEAR = [ 1, 32, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335 ]

    # *weekOfYear(date, startOfWeek)*
    #
    # Get the week of the year for the given `date`, where `startOfWeek` is the
    # week day on which our week starts, either Sunday or Monday.
    weekOfYear = (date, startOfWeek) ->
      fields = [ date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate() ]
      date = new Date(Date.UTC.apply Date.UTC, fields)
      nyd = new Date(Date.UTC(date.getUTCFullYear(), 0, 1))
      diff = (date.getTime() - nyd.getTime()) / DAY
      day = date.getUTCDay()
      if nyd.getUTCDay() is startOfWeek
        weekStart = 0
      else
        weekStart = 7 - nyd.getUTCDay() + startOfWeek
        weekStart = 1 if weekStart is 8
      remaining = diff - weekStart
      week = 0
      if diff >= weekStart
        week++
        diff -= weekStart
        week += Math.floor(diff / 7)
      week

    # *isoWeek(date)*
    #
    # Get the [ISO week](http://en.wikipedia.org/wiki/ISO_week_date) of the year
    # for the given `date`.
    isoWeek = (date) ->
      nyy = date.getUTCFullYear()
      nyd = new Date(Date.UTC(nyy, 0, 1)).getUTCDay()
      offset = if nyd > 1 and nyd <= 4 then 1 else 0
      week = weekOfYear(date, 1) + offset
      if week is 0
        ny = new Date(Date.UTC(date.getUTCFullYear() - 1, 0, 1))
        nyd = ny.getUTCDay()
        nyy = ny.getUTCFullYear()
        week = if nyd is 4 or (nyd is 3 and isLeapYear(nyy)) then 53 else 52
        [ week, date.getUTCFullYear() - 1 ]
      else if week is 53 and not (nyd is 4 or (nyd is 3 and isLeapYear(nyy)))
        [ 1, date.getUTCFullYear() + 1 ]
      else
        [ week, date.getUTCFullYear() ]

    # *dialHours(date)*
    #
    # Get the hour for a 12 hour clock for the given `date`.
    dialHours = (date) ->
      hours = Math.floor(date.getUTCHours() % 12)
      if hours is 0 then 12 else hours

    recurse = (request, splat...) ->
      convert.call null, null, request, splat.concat([ request.zone, request.locale ]), 0

    splitOffset = (offset) ->
      offset = Math.abs(offset)
      offset -= (millis = offset % 1000)
      offset /= 1000
      offset -= (seconds = offset % 60)
      offset /= 60
      offset -= (minutes = offset % 60)
      hours = offset / 60
      [ hours, minutes, seconds, millis ]

    # Map the specifiers to a function that implements the specifier. Rather
    # than document each one, please use a [Unix
    # Date](http://en.wikipedia.org/wiki/Date_%28Unix%29) pattern reference if
    # you can't deduce the intent from the function.
    #
    # TODO Maybe a switch statement is smaller?
    specifiers =
      a: (date, locale) -> locale.day.abbrev[date.getUTCDay()]
      A: (date, locale) -> locale.day.full[date.getUTCDay()]
      d: (date) -> date.getUTCDate()
      e: (date) -> date.getUTCDate()
      j: (date) ->
        month = date.getUTCMonth()
        days = MONTH_DAY_OF_YEAR[month]
        if month > 2 and isLeapYear(date.getUTCFullYear())
          days++
        days += date.getUTCDate() - 1
        days
      u: (date) ->
        day = date.getUTCDay()
        day = 7 if day is 0
        day
      w: (date) -> date.getUTCDay()
      U: (date) -> weekOfYear(date, 0)
      W: (date) -> weekOfYear(date, 1)
      V: (date) -> iso = isoWeek(date)[0]
      G: (date) -> iso = isoWeek(date)[1]
      g: (date) -> iso = isoWeek(date)[1] % 100
      m: (date) -> date.getUTCMonth() + 1
      h: (date, locale) -> locale.month.abbrev[date.getUTCMonth()]
      b: (date, locale) -> locale.month.abbrev[date.getUTCMonth()]
      B: (date, locale) -> locale.month.full[date.getUTCMonth()]
      y: (date) -> date.getUTCFullYear() % 100
      Y: (date) -> date.getUTCFullYear()
      C: (date) -> Math.floor(date.getFullYear() / 100)
      D: (date) -> tz(date, "%m/%d/%y")
      x: (date, locale, request) ->
        posix = convertToPOSIX request, date.getTime()
        recurse request, posix, locale.dateFormat
      F: (date) -> tz(date, "%Y-%m-%d")
      l: (date) -> dialHours(date)
      I: (date) -> dialHours(date)
      k: (date) -> date.getUTCHours()
      H: (date) -> date.getUTCHours()
      P: (date, locale) ->
        locale.meridiem[Math.floor(date.getUTCHours() / 12)].lower
      p: (date, locale) ->
        locale.meridiem[Math.floor(date.getUTCHours() / 12)].upper
      M: (date) -> date.getUTCMinutes()
      s: (date) -> Math.floor(date.getTime() / 1000)
      S: (date) -> date.getUTCSeconds()
      N: (date) -> (date.getTime() % 1000) * 1000000
      r: (date) -> tz(date, "%I:%M:%S %p")
      R: (date) -> tz(date, "%H:%M")
      T: (date) -> tz(date, "%H:%M:%S")
      X: (date, locale, request) ->
        posix = convertToPOSIX request, date.getTime()
        recurse request, posix, locale.timeFormat
      c: (date, locale, request) ->
        posix = convertToPOSIX request, date.getTime()
        recurse request, posix, locale.dateTimeFormat
      z: (date, locale, request, delimiters) ->
        offset = request.entry.offset
        parts = (pad(part, 2, "0") for part in splitOffset offset)
        parts[0] = "-#{parts[0]}" if offset < 0
        if delimiters
          switch delimiters.length
            when 1
              parts.slice(0, 2).join(":")
            when 2
              parts.slice(0, 3).join(":")
            else
              if parts[2] isnt "00"
                parts.slice(0, 3).join(":")
              else if parts[1] isnt "00"
                parts.slice(0, 2).join(":")
              else parts[0]
        else
          parts.slice(0, 2).join("")
      # Alphabetic time zone abbreviation.
      Z: (date, locale, request) ->
        # Repeats a few lines of code from `convertToPOSIX`. No real desire
        # optimize for size by wrapping it up in a function.
        request.entry?.abbrev or "UTC"

    # Some format specifiers have padding characters. We specify the padding
    # counts separately, instead of adding padding in the format specifier
    # method. Not only does this make it easier to implement the specifiers, the
    # user can disable padding with modifiers, so it is easier to implement the
    # toggle if padding is a second step. Thus, we get the number value first,
    # then pad using the default or user specified padding.
    padding =
      d: 2
      U: 2
      W: 2
      V: 2
      g: 2
      m: 2
      j: 3
      C: 2
      I: 2
      H: 2
      k: 2
      M: 2
      S: 2
      N: 9
      y: 2

    # Map the padding specifier character to a padding function that will pad
    # using the specified character. The `-` specifier means no padding and
    # overrides the default padding.
    paddings = { "-": (number) -> number }
    for flag, ch of { "_": " ", "0": "0" }
      paddings[flag] = do (ch) ->
        (number, count) -> pad(number, count, ch)

    # *pad(number, count, char)*
    #
    # Pad the given `number` with the `count` of the padding `char`.
    pad = (number, count, char) ->
      string = String(number)
      "#{new Array((count - string.length) + 1).join(char)}#{string}"

    # Map of transformation specifier to a function that will perform the
    # transformation. Only upcase at the moment.
    transforms =
      none: (value) -> value
      "^": (value) -> value.toUpperCase()

    # Implementation.
    (request, wallclock, rest) ->
      # Convert the `wallclock` seconds since the epoch to a `Date` to get to
      # the fields. `output` will gather our formatted string.
      date    = new Date(wallclock)
      output  = []

      locale = request.locales[request.locale]

      # While there is more string to parse.
      while rest.length
        # Attempt to match format specifier.
        match = ///
          ^           # start
          (.*?)       # non-specifier stuff
          %           # start specifier
          (?:
            %           # literal precent
            |
            (?:
              ([-0_^]?)   # padding
              |
              (\:{0,3})   # offset delimiters
            )
            (           # field
              [aAcdDeFHIjklMNpPsrRSTuwXUWVmhbByYcGgCxzZ]
            )
          )
          (.*)        # rest
          $           # end
        ///.exec rest

        # If we match, then replace the specifier with the formatted date field.
        if match
          [ prefix, flags, delimiters, specifier, rest ] = match.slice(1)

          # We have a specifier.
          if specifier

            # Get out specifier field value.
            value = specifiers[specifier](date, locale, request, delimiters)

            # Apply padding, if the specifier is padded. The `k` specifier is
            # padded with spaces, but all others are padded with zeros. We apply
            # the user override, if any, and call the appropriate padding
            # function.
            if padding[specifier]
              style = if specifier is "k" then "_" else "0"
              if flags
                style = flags[0] if paddings[flags[0]]
              value = paddings[style](value, padding[specifier])

            # Apply any user specified transformations. This is only upper case,
            # and it implies that the value is not numeric, there is never more
            # than one modifier.
            transform = transforms.none
            if flags?
              transform = transforms[flags[0]] or transform
            value = transform(value)

            # Add the prefix and converted value to the output.
            output.push prefix if prefix?
            output.push value

          # We have a literal percent.
          else
            output.push "%"

        # Otherwise, we're going to be done with this loop.
        else if rest.length
          output.push rest
          rest = ""

      # Gather up our output into a string.
      output.join ""

  ##### makeDate(year, month, day, hours, minutes, seconds, milliseconds)
  # 
  # Create a wallclock time record from the given units extracted from a parsed
  # date string.

  # Wrap helper methods in a function scope.
  makeDate = do ->
    # Push a zero onto date fields if the value is undefined.
    zeroUnless = (date, value) ->
      if value?
        date.push parseInt value, 10
      else
        date.push 0

    # This method will substitute for missing values. If given only a time, it
    # will use the current date. If given only a date, it will use midnight for
    # the time. If given a year without a month or day, it is the first of the
    # year. If given a month with no day, it will use the first of the month.
    (year, month, day, hours, minutes, seconds, milliseconds) ->
      date = []

      # No year, and we have a time with no date, so we use todays date.
      # FIXME: What about timezone?
      if not year?
        # FIXME Test this branch.
        now = new Date(CLOCK())
        date.push now.getUTCFullYear()
      else
        date.push parseInt year, 10

      # No month? If we have no year, and we have a time with no date, so
      # we use todays date. If we have a year, then we have a date with no
      # month, so we assume January.
      if not month?
        if not year?
          date.push now.getUTCMonth()
        else
          date.push 0
      else
        date.push parseInt(month, 10) - 1

      # No day? If we have no year, and we have a time with no date, so we use
      # todays date. If we have a year, then we have a date with no day, so we
      # assume the first of the month.
      if not day?
        if not month?
          date.push now.getUTCDate()
        else
          date.push 1
      else
        date.push parseInt day, 10

      # For hours, minutes, seconds, and milliseconds, if they are not
      # specified, then they are zero.
      zeroUnless date, hours
      zeroUnless date, minutes
      zeroUnless date, seconds
      zeroUnless date, milliseconds

      # Return wallclock millseconds since the epoch.
      Date.UTC.apply Date.UTC, date

  # Parse a date, possibly fuzzy.
  parse = (request, pattern) ->
    # Best foot forward, an RFC 822 date.
    if match = ///
      ^             # start
      (.*?)         # before
      (
        \w{3}         # day of week
      )
      ,             # comma
      \s+           # spaces
      (
        \d{1,2}       # day of month
      )
      \s+           # spaces
      (
        \w{3}         # month
      )
      \s+           # spaces
      (
        \d{2,4}       # year
      )
      \s+           # spaces
      (
        \d{2}         # hour
      )
      :             # colon
      (
        \d{2}         # minutes
      )
      (?:
        :             # colon
        (
          \d{2}         # seconds
        )
      )?
      \s*
      (?:
        (
          [A-IK-Z]      # military
          |
          UT | GMT      # UTC
          |
          [ECMP][SD]T   # United States
        )
        |
        (
          [-+]?
          \d{4}
        )
      )?
      (.*)
      $
    ///i.exec pattern
      [ before,
        dow, day, month, year,
        hours, minutes, seconds,
        zone, offset,
        after ] = match.slice 1

      dow = dow.toLowerCase()
      for abbrev in request.locales[request.locale].day.abbrev
        if dow is abbrev.toLowerCase()
          dow = null
          break
      if dow
        throw new Error "bad weekday"
      month = month.toLowerCase()
      for abbrev, i in request.locales[request.locale].month.abbrev
        if month is abbrev.toLowerCase()
          month = i
          break
      if typeof month is "string"
        throw new Error "bad month"

      seconds or= "0"
      offset  or= "0"

      [ day, year, hours, minutes, seconds, offset ] = (
        parseInt num, 10 for num in [ day, year, hours, minutes, seconds, offset ]
      )
      
      wallclock = makeDate year, month + 1, day, hours, minutes, seconds, 0
      if offset
        posix = wallclock - Math.floor(offset / 100) * HOUR
      else
        posix = convertToPOSIX request, wallclock
      return posix

    # Second best foot forward, an ISO date. An ISO date can also be YYYY, but we catch
    # that case later on, so we don't pluck YYYY/MM or some such now.
    if match = ///
      ^             # start
      (.*?)         # before
      (?:           # year 
        (\d\d\d\d)    # four digit year
          -           # hyphen
        (\d\d)        # two digit month
        (?:           # optional date
            -           # hypen
          (\d{2})       # two digit date
        )?
      |             # year with no hyphens
        (\d{4})       # year
        (\d{2})       # month
        (\d{2})?      # date
      )
      (?:           # optional time
        (?:\s+|T)     # time delimiter
        (\d\d)        # hours
        (?:           # optional minutes
          :?            # optional colon
          (\d\d)        # minutes 
          (?:           # optional seconds
            :?            # optional colon
            (\d\d)        # seconds
            (?:           # optional milliseconds
              \.            # period
              (\d+)         # milliseconds
            )?
          )?
        )?
      )?
      (?:           # optional zone 
        (?:\s+|Z)     # zone delimiter
        (
          [+-]      # sign
          \d{2}     # hours
          (?:         # optional minutes
            :?          # optional colon
            \d{2}       # minutes
          )?
        )
      )?
      (.*)          # after
      $
    ///.exec(pattern)
      # Stuff before the matched ISO date.
      before = match.splice(0, 2).pop()
      
      # See if we matched the hyphenated date.
      date = match.splice(0, 3)
      [ year, month, day ] = date if date[0]?

      # See if we matched the all numbers date.
      date = match.splice(0, 3)
      [ year, month, day ] = date if date[0]?

      # See if we matched the a time.
      time = match.splice(0, 4)
      [ hours, minutes, seconds, milliseconds ] = time if time[0]?

      # See if we matched a zone offset. A zone offset is ISO an arbitrary
      # offset and has no information on location or summer time rules.
      zone = match.shift()
      zoneOffset = offsetInMilliseconds(zone) if zone?

      # Stuff fater the matched ISO date.
      after = match.pop()

      # If we nailed it, let's stop here.
      remaining = (before + after).replace(/\s+/, "").length
      if remaining is 0
        wallclock = makeDate year, month, day, hours, minutes, seconds, milliseconds
        return convertToPOSIX request, wallclock
  
    # Look for a time, either in the whole pattern, or in what's left after the
    # date consumed a date-like thing.

    # Now let's split what we've got and look for locale specific words that are
    # meaningful.

    # If we're willing to be fuzzy, then we'll look harder. Maybe we have a
    # bunch of regular expressions to run, that will extract locale specific
    # strings, say, this looks like an hour, this looks like a day of the week,
    # this looks like a date. So /at (\d+)\s*([pa]m?)/i or some such, with ()
    # for place holders for bits of the pattern that won't match.

    # Let's start by parsing ISO, UNIX and not very fuzzy dates. Really, you can
    # just tell the user to try harder, or else prompt with a date format.

  ##### offsetInMilliseconds(pattern)

  # Convert offset, read from our time zone database, or from an ISO date, into
  # milliseconds so we can use it to adjust milliseconds since the epoch.
  offsetInMilliseconds = (pattern) ->
    match = /^(-?)(\d+)(?::(\d+))?(?::(\d+))?$/.exec(pattern).slice(1)
    match[0] += "1"
    [ sign, hours, minutes, seconds ] = (
      parseInt(number or "0", 10) for number in match
    )
    offset  = hours   * HOUR
    offset += minutes * MINUTE
    offset += seconds * SECOND
    offset *= sign
    offset

  ##### actualize(entry, rule, year)

  # Convert a daylight savings time rule into miliseconds since the epoch. We
  # use `Date` because it gives us the day of the week. No error checking on
  # rule, it is assumed to be correct in the database. 
  actualize = (request, rule, year) ->
    # Split up the time of day.
    match = /^(\d+):(\d+)(?::(\d+))?u?$/.exec(rule.time).slice(1)
    [ hours, minutes, seconds ] = (parseInt number or 0, 10 for number in match)

    # Split up the daylight savings time day.
    match = ///
      ^             # start
      (?:
        (\d+)         # a fixed date
        |
        last(\w+)     # last day of month
        |
        (\w+)>=(\d+)  # day greater than or equal to date
      )
      $             # end
    ///.exec(rule.day)

    # A fixed date.
    if match[1]
      [ month, day ] = [ rule.month, parseInt(match[1], 10) ]
      date = new Date(Date.UTC(year, month, day, hours, minutes, seconds))

    # Last of a particular day of the week in the month.
    else if match[2]
      for day, i in en_US.day.abbrev
        if day is match[2]
          index = i
          break
      day = daysInMonth(rule.month, year)
      loop
        date = new Date(Date.UTC(year, rule.month, day, hours, minutes, seconds))
        if date.getUTCDay() is index
          break
        day--

    # A day of the week greater than or equal to a day of the month.
    else
      min = parseInt match[4], 10
      for day, i in en_US.day.abbrev
        if day is match[3]
          index = i
          break
      day = 1
      loop
        date = new Date(Date.UTC(year, rule.month, day, hours, minutes, seconds))
        if date.getUTCDay() is index and date.getUTCDate() >= min
          break
        day++

    # Return wallclock milliseconds since the epoch.
    if /u$/.test rule.time
      fields = new Date date.getTime() + offsetInMilliseconds(request.entry.offset) + offsetInMilliseconds(rule.save)
      posix = date.getTime()
    else
      wallclock = date.getTime()
      fields = new Date wallclock

    # Sortable only works if there are no rules on the same day.
    sortable = fields.getUTCFullYear() * 10000 + fields.getUTCMonth() * 100 + fields.getUTCDate()

    { sortable, rule, wallclock, year, posix }

  iso8601 = (date) -> new Date(date).toISOString().replace(/\..*$/, "")
      
  search = (zone, clock, milliseconds) ->
    low = 1
    high = zone.length - 1
    while low <= high
      mid = low + ((high - low) >>> 1)
      compare = milliseconds - zone[mid][clock]
      if compare > 0
        low = mid + 1
      else if compare < 0
        high = mid - 1
      else
        return mid
    low - 1

  # Convert the UTC epoch seconds to epoch seconds in the given time zone.
  convertToWallclock = (request, posix) ->
    return posix if request.zone is "UTC"
    zone = request.zones[request.zone]
    index = search zone, "posix", posix
    request.entry = zone[index]
    return posix + request.entry.offset

  # Convert from a wallclock milliseconds since the epoch to UTC milliseconds
  # since the epoch.
  #
  # Times are record in zones and rules in the database, for the most part, in
  # wallclock time. This means that for conversion from wallclock to posix, the
  # times in the database are right. Remember that our wallclock time is an
  # imaginary construct, it is wallclock time represented by the time on the
  # posix timeline with the same date fields.
  #
  # It is easy to forget this, somehow, and to ponder how to calculate the
  # wallclock time, how to apply the savings of the previous period. These are
  # only challenges when going from posix to wallclock.
  convertToPOSIX = (request, wallclock) ->
    return wallclock if request.zone is "UTC"
    zone = request.zones[request.zone]
    request.entry = entry = zone[search zone, "wallclock", wallclock]
    diff = wallclock - entry.wallclock
    if 0 < diff < entry.save then null else wallclock - entry.offset

  parseAdjustment = (pattern) ->
    if match = ///
        ^                 # start
        \s*               # leading whitespace
        (?:
          ([+-]?)         # add or subtract
          \s*             # optional space
          (\d+)           # count
          \s+             # manditory space
        )?
        ( year            # unit
        | month
        | day
        | hour
        | minute
        | second
        | milli(?:second)?
        | sunday
        | monday
        | tuesday
        | wednesday
        | thursday
        | friday
        | saturday
        )
        (s)?              # optional plural
        (?:
          \s+               # delimiting white space
          (\d+)             # position
        )?
        \s*               # trailing whitespace
        $                 # end
      ///i.exec pattern
      [ sign, count, unit, plural, position ] = match[1..]
      if position
        if not count and not plural
          adjustment = { unit, position }
      else if count
        adjustment = { sign, count, unit }
    adjustment

  adjust = do ->
    FIELD =
      year:         0
      month:        1
      day:          2
      hour:         3
      minute:       4
      second:       5
      milli:        6
      millisecond:  6

    TIME =
      milli:        1
      millisecond:  1
      second:       SECOND
      minute:       MINUTE
      hour:         HOUR

    SIGN_OFFSET =
      "-":  -1
      "+":  +1

    DAYS = [
      "sunday"
      "monday"
      "tuesday"
      "wednesday"
      "thursday"
      "friday"
      "saturday"
    ]

    ASSIGNMENT =
      year:
        min: 0
        max: Number.MAX_VALUE
      month:
        min: 1
        max: 12
      day:
        min: 1
        max: 12

    explode = (wallclock) ->

    (request, posix, adjustment) ->
      { sign, count, unit } = adjustment

      sign    or= "+"
      unit      = unit.toLowerCase()
      increment = SIGN_OFFSET[sign]
      offset    = parseInt(count, 10)

      # Hourly math in UTC.
      if millis = TIME[unit]
        posix += offset * increment * millis
      # Daily math in wallclock time.
      else
        wallclock = convertToWallclock request, posix
        if ~(index = DAYS.indexOf(unit))
          while offset isnt 0
            wallclock += increment * DAY
            offset-- if new Date(wallclock).getUTCDay() is index
        else if unit is "day"
          # Accounts for leap years and days of month.
          wallclock += offset * increment * DAY
        else
          # Explode into individual fields for month and year math.
          date = new Date(wallclock)
          fields = [
            date.getUTCFullYear()
            date.getUTCMonth()
            date.getUTCDate()
            date.getUTCHours()
            date.getUTCMinutes()
            date.getUTCSeconds()
            date.getUTCMilliseconds()
          ]
          # It is easier to move through the months ourselves that it is to
          # move by milliseconds.
          if unit is "month"
            offset *= increment
            while offset isnt 0
              month = fields[FIELD.month]
              if month is 0 and offset < 0
                fields[FIELD.month] = 11
                fields[FIELD.year]--
              else if month is 11 and offset > 0
                fields[FIELD.month] = 0
                fields[FIELD.year]++
              else
                fields[FIELD.month] += increment
              offset -= increment
              
          # Adjust the year. 
          else if unit is "year"
            forward = offset / Math.abs(offset)
            fields[FIELD.year] += offset * increment

          # Create a wallclock date.
          wallclock = Date.UTC.apply Date.UTC, fields

        # If we landed on a time missing due to summer time spring forward, we
        # will move to the day using 24 hours.
        if not (posix = convertToPOSIX(request, wallclock))?
          wallclock += DAY * increment
          posix = convertToPOSIX request, wallclock
          posix -= DAY * increment

      posix

  extend = (to, from) ->
    to[key] = value for key, value of from
    to

  append = (context, request, value, key) ->
    request[key] or= extend {}, context[key]
    extend request[key], value

  zoneinfo = (context, table) ->
    zone = []
    name = table.shift()
    offset = table.shift()
    abbrevs = []
    abbrevs.push(table.shift()) while typeof table[0] != "number"
    for i in [0...Math.floor(table.length / 4)]
      j = i * 4
      zone.push entry =
        posix: Math.round(table[j] * 1000 * 100)
        wallclock: Math.round((table[j] - table[j + 1]) * 1000 * 100)
        save: Math.round(table[j + 2] * 1000 * 60 * 10)
        abbrev: abbrevs[table[j + 3]]
        offset: offset
      offset = entry.wallclock - entry.posix
    zone.push({ posix: Number.MIN_VALUE, wallclock: Number.MIN_VALUE, save: 0, abbrev: abbrevs[table.pop()], offset })
    context.zones[name] = zone.reverse()
  
  # Creates a new function.
  convert = (tz, context, splat, length) ->
    # Create a default request.
    request = { adjustments: [] }

    # If our first argument is anything other than a date, we are creating a new
    # `tz` function.
    count = 0
    date = null

    # We shift our way through the parameters. We shift because when we
    # encounter an array that is not an array of date fields, we'll flatten the
    # array, unshifting it onto our parameter list.

    #
    index = 0
    partial = []
    while splat.length
      partial.push argument = splat.shift()
      type = typeof argument
      # A number as the first argument is POSIX time.
      if type is "number" and index is length
        request.date = argument
      # Strings come in many forms.
      else if type is "string"
        # Arguments with a "%" are date formats.
        if argument.indexOf("%") != -1
          request.format or= argument
        # Arguments that look like locales are locales.
        else if /^\w{2}_\w{2}$/.test argument
          request.locale or= argument
        # Adjustments are pretty easy to spot too.
        else if adjustment = parseAdjustment argument
          request.adjustments.push adjustment
        # At this point, if it has slashes but no numbers, the only thing it
        # could be is a timezone.
        else if context.zones[argument]
          request.zone or= argument
        # It is a date or it is jibberish.
        else if index is length
          request.date = argument
      # A clock is the only function we accept.
      else if type is "function"
        request.clock = argument
      # An array is either an array of date fields, it it is in the first
      # position, otherwise it is an array of parameters to flatten.
      else if Array.isArray argument
        if index is length and typeof argument[0] is "number"
          request.date = argument
        else
          splat.unshift object for object in argument
      # Objects come in many forms.
      else if type is "object"
        # We use an object as a flag to request now for date.
        if index is length and (argument is tz.now or argument.getTime)
          request.date = argument
        # Otherwise, we look for locale definitions.
        else if /^\w{2}_\w{2}$/.test argument.name
          partial.pop()
          append context, request, {}, "locales"
          request.locales[argument.name] = argument
        # Timezone data has a particular flavor.
        else if argument.z
          partial.pop()
          zoneinfo context, argument.z
      # Next, please.
      index++

    # Copy over any timezone or locale data that was not extended.
    for key in [ "zones", "rules", "locales", "clock" ]
      request[key] or= context[key]

    # Add or replace locales with the given locale data structure. If a locale
    # in the data structure already exists, the locale is overwritten.

    # Add or replace time zones with the given locale data structure. If a time
    # zone in the data structure already exists, the time zone is overwritten.

    # Set the clock function which will return the current time when needed.
    # This is useful for debugging or for providing a clock that will check a
    # server for a client independent time.
    if (date = request.date)?

      # Land of the the author, home of the brave.
      request.locale or= "en_US"

      # UTC is the default time zone for good reason.
      request.zone or= "UTC"
      request.entry = UTC[0]
      
      throw new Error "unknown locale" unless request.locales[request.locale]

      # Convert the date argument to seconds since the epoch. The seconds since
      # the epoch is really way to have a record used to store date fields. The
      # fields are accessed by converting the epoch into a Date object. The zone
      # offset field values of the converted object are meaningless and the UTC
      # offset field values represent our working time zone.
      if typeof date is "string"

        # Parse will apply the time zone offset.
        unless (posix = parse request, date)?
          throw new Error "invalid date"

      else if typeof date is "number"
        posix = date
      # Get the current time if the date is the now flag.
      else if date is tz.now
        posix = (request.clock or context.clock)()

      # Convert from date to epoch seconds if necessary.
      else if date.getTime
        posix = request.date.getTime()

      # Apply date math if any.
      for adjustment in request.adjustments
        posix = adjust request, posix, adjustment

      # Apply format if any. The record is adjusted to the current timezone for
      # use as a date/time field record.
      if request.format
        wallclock = convertToWallclock request, posix
        token = format request, wallclock, request.format
    
      # Otherwise return POSIX time.
      else
        token = posix
    else
      token = (splat...) -> convert(token, request, partial.concat(splat), partial.length)
      extend token, tz

    token
       
  # The all purpose exported function.
  exports.tz = tz = do ->
    context =
      zones: { UTC }
      rules: {}
      locales: { en_US }
      clock: CLOCK
    (splat...) -> convert tz, context, splat, 0

  # Flag passed to tz in the place of a POSIX time or date string to  indicate
  # that the time to use is the current time according to the clock function.
  tz.now = {}
