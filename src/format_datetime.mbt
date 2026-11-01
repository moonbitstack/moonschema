// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The four formats that name a point in time or a span of it: `date`, `time`,
// `date-time` (RFC 3339 §5.6) and `duration` (RFC 3339 Appendix A).
//
// The calendar is moondate's: which day a month has, and whether a year is a
// leap one, is arithmetic this library has no business repeating. What is read
// here is the shape of the text, because a validator's job is to refuse a
// string before asking any library what it means.

///|
/// The digit at `index`, or `-1` when it is not one.
///
/// ASCII only: `1963-06-1৪` is a Bengali four, and a year with one in it is not
/// a year a parser reading ASCII would ever produce.
fn digit_at(text : StringView, index : Int32) -> Int32 {
  if index < 0 || index >= text.length() {
    return -1
  }
  let code = text[index].to_int()
  if code < 0x30 || code > 0x39 {
    return -1
  }
  code - 0x30
}

///|
/// `count` digits from `from` as the number they spell, or `None` when they are
/// not all digits or are not all there.
fn number_at(text : StringView, from : Int32, count : Int32) -> Int32? {
  let mut value = 0
  for i = 0; i < count; i = i + 1 {
    let digit = digit_at(text, from + i)
    if digit < 0 {
      return None
    }
    value = value * 10 + digit
  }
  Some(value)
}

///|
/// Whether the day exists: the calendar's answer, asked of moondate, whose
/// months know their length and whose years know the century rule.
fn is_calendar_day(year : Int32, month : Int32, day : Int32) -> Bool {
  let _ = @moondate.Date::new(year, month, day) catch { _ => return false }
  true
}

///|
/// An RFC 3339 §5.6 `full-date`: `YYYY-MM-DD`, four digits for the year, and a
/// day the month actually has.
fn is_date(text : String) -> Bool {
  guard text.length() == 10 else { return false }
  guard text[4] == '-' && text[7] == '-' else { return false }
  let year = match number_at(text[:], 0, 4) {
    Some(found) => found
    None => return false
  }
  let month = match number_at(text[:], 5, 2) {
    Some(found) => found
    None => return false
  }
  let day = match number_at(text[:], 8, 2) {
    Some(found) => found
    None => return false
  }
  is_calendar_day(year, month, day)
}

///|
/// The reading of a `full-time`, and the one thing that makes it more than a
/// regular expression: whether a `:60` is a leap second or a typo.
priv struct Time {
  /// Seconds since midnight, the leap second counting as 59 for the arithmetic.
  seconds : Int32
  /// Offset from UTC in seconds, east positive.
  offset : Int32
  /// Whether the second field was 60.
  leap : Bool
}

///|
/// An RFC 3339 §5.6 `full-time`: `HH:MM:SS[.frac]` and an offset, which RFC 3339
/// makes mandatory — `12:00:00` alone names no instant.
fn read_time(text : StringView) -> Time? {
  guard number_at(text, 0, 2) is Some(hour) else { return None }
  guard number_at(text, 3, 2) is Some(minute) else { return None }
  guard number_at(text, 6, 2) is Some(second) else { return None }
  guard text[2] == ':' && text[5] == ':' else { return None }
  guard hour <= 23 && minute <= 59 && second <= 60 else { return None }
  let mut i = 8
  // The fraction is optional and may be any number of digits: `…999999999999999Z`
  // is a time, however little a reader can do with it.
  if i < text.length() && text[i] == '.' {
    i = i + 1
    let start = i
    while i < text.length() && digit_at(text, i) >= 0 {
      i = i + 1
    }
    guard i > start else { return None }
  }
  guard i < text.length() else { return None }
  let offset = if text[i] == 'Z' || text[i] == 'z' {
    i = i + 1
    0
  } else if text[i] == '+' || text[i] == '-' {
    let negative = text[i] == '-'
    guard number_at(text, i + 1, 2) is Some(offset_hour) else { return None }
    guard number_at(text, i + 4, 2) is Some(offset_minute) else { return None }
    guard text[i + 3] == ':' else { return None }
    guard offset_hour <= 23 && offset_minute <= 59 else { return None }
    i = i + 6
    let span = offset_hour * 3600 + offset_minute * 60
    if negative {
      -span
    } else {
      span
    }
  } else {
    return None
  }
  guard i == text.length() else { return None }
  let time : Time = {
    seconds: hour * 3600 +
    minute * 60 +
    (if second == 60 { 59 } else { second }),
    offset,
    leap: second == 60,
  }
  Some(time)
}

///|
/// A leap second exists only at 23:59:60 UTC, and RFC 3339 writes it in local
/// time: `01:29:60+01:30` is that same moment, `23:58:60Z` is not one at all.
fn is_leap_second_place(time : Time) -> Bool {
  // Wrapped in seconds first: a local time west of UTC puts the instant on the
  // day before, and dividing a negative number would round towards zero and
  // lose the minute it crossed.
  let utc = time.seconds - time.offset
  let day = 24 * 3600
  let folded = (utc % day + day) % day
  folded / 60 == 23 * 60 + 59
}

///|
/// Whether a version lets a bare time be a leap second.
///
/// v1 reads `time` against RFC 9557, which dropped it: a time with no date on
/// it cannot say which leap second it is, so the second field stops at 59.
/// `date-time` still has a date to say it with, and keeps the leap second.
priv enum Leap {
  Allowed
  Refused
}

///|
/// Whether a time reads as an instant: a `:60` must be at the one place a leap
/// second can be, and anything earlier is a time wherever it is.
fn is_instant(time : Time, leap : Leap) -> Bool {
  if !time.leap {
    true
  } else {
    match leap {
      Allowed => is_leap_second_place(time)
      Refused => false
    }
  }
}

///|
/// An RFC 3339 §5.6 `full-time`.
fn is_time(text : String, leap : Leap) -> Bool {
  match read_time(text[:]) {
    Some(time) => is_instant(time, leap)
    None => false
  }
}

///|
/// An RFC 3339 §5.6 `date-time`: a `full-date`, `T` in either case, and a
/// `full-time`.
fn is_date_time(text : String) -> Bool {
  guard text.length() > 11 else { return false }
  let separator = text[10]
  guard separator == 'T' || separator == 't' else { return false }
  if !is_date(text[0:10].to_owned()) {
    return false
  }
  match read_time(text[:][11:]) {
    Some(time) => is_instant(time, Allowed)
    None => false
  }
}

///|
/// An RFC 3339 Appendix A `duration`.
///
/// The grammar is a chain, not a set: `P1Y2D` is not a duration because a year
/// may be followed by a month and then by a day, never by a day alone. So this
/// reads it the way the grammar is written, one production at a time, rather
/// than counting unit letters in any order.
fn is_duration(text : String) -> Bool {
  let view = text[:]
  if view.length() < 2 || view[0] != 'P' {
    return false
  }
  // `dur-date / dur-time / dur-week`: a duration may be all time and no date,
  // which is `PT36H` and its kind.
  if view[1] == 'T' {
    guard read_duration_time(view, 2) is Some(after) else { return false }
    return after == view.length()
  }
  let (next, weeks) = read_duration_date(view, 1)
  guard next is Some(after) else { return false }
  let mut i = after
  if weeks {
    // A week is its own form: `P1Y2W` is not one, and neither is `P1WT1H`.
    return i == view.length()
  }
  if i < view.length() && view[i] == 'T' {
    i = i + 1
    guard read_duration_time(view, i) is Some(after) else { return false }
    i = after
  }
  i == view.length()
}

///|
/// `1*DIGIT` from `from`, and the index just past them, or `None` when there are
/// none — every number in a duration is at least one digit.
fn skip_digits(text : StringView, from : Int32) -> Int32? {
  let mut i = from
  while i < text.length() && digit_at(text, i) >= 0 {
    i = i + 1
  }
  if i == from {
    None
  } else {
    Some(i)
  }
}

///|
/// The date half of a duration, and whether it was the week form.
///
/// `dur-date = (dur-day / dur-month / dur-year) [dur-time]`, where each of the
/// three is built out of the one before it: a year may be followed by a month
/// and then by a day, and a month by a day. `P1Y2D` therefore stops at `2D`,
/// which the grammar has nowhere to put.
fn read_duration_date(text : StringView, from : Int32) -> (Int32?, Bool) {
  let at = match skip_digits(text, from) {
    Some(found) => found
    None => return (None, false)
  }
  guard at < text.length() else { return (None, false) }
  match text[at] {
    'W' => (Some(at + 1), true)
    'D' => (Some(at + 1), false)
    'M' => {
      let mut next = at + 1
      match skip_digits(text, next) {
        Some(after) =>
          if after < text.length() && text[after] == 'D' {
            next = after + 1
          }
        None => ()
      }
      (Some(next), false)
    }
    'Y' => {
      let mut next = at + 1
      match skip_digits(text, next) {
        Some(after) =>
          if after < text.length() && text[after] == 'M' {
            next = after + 1
            match skip_digits(text, next) {
              Some(day) =>
                if day < text.length() && text[day] == 'D' {
                  next = day + 1
                }
              None => ()
            }
          }
        None => ()
      }
      (Some(next), false)
    }
    _ => (None, false)
  }
}

///|
/// The time half of a duration: `dur-time = "T" (dur-hour / dur-minute /
/// dur-second)`, each of which may be followed by the one below it and by
/// nothing else.
fn read_duration_time(text : StringView, from : Int32) -> Int32? {
  let at = match skip_digits(text, from) {
    Some(found) => found
    None => return None
  }
  guard at < text.length() else { return None }
  match text[at] {
    'H' => {
      let mut next = at + 1
      match skip_digits(text, next) {
        Some(after) =>
          if after < text.length() && text[after] == 'M' {
            next = after + 1
            match skip_digits(text, next) {
              Some(second) =>
                if second < text.length() && text[second] == 'S' {
                  next = second + 1
                }
              None => ()
            }
          }
        None => ()
      }
      Some(next)
    }
    'M' => {
      let mut next = at + 1
      match skip_digits(text, next) {
        Some(after) =>
          if after < text.length() && text[after] == 'S' {
            next = after + 1
          }
        None => ()
      }
      Some(next)
    }
    'S' => Some(at + 1)
    _ => None
  }
}
