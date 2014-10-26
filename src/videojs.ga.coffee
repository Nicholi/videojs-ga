##
# ga
# https://github.com/mickey/videojs-ga
#
# Copyright (c) 2013 Michael Bensoussan
# Licensed under the MIT license.
##

videojs.plugin 'ga', (options = {}) ->
  # this loads options from the data-setup attribute of the video tag
  dataSetupOptions = {}
  if @options()["data-setup"]
    parsedOptions = JSON.parse(@options()["data-setup"])
    dataSetupOptions = parsedOptions.ga if parsedOptions.ga

  defaultsEventsToTrack = [
    'loaded', 'percentsPlayed', 'secondsPlayed', 'start',
    'end', 'seek', 'play', 'pause', 'resize',
    'volumeChange', 'error', 'fullscreen'
  ]
  eventsToTrack = options.eventsToTrack || dataSetupOptions.eventsToTrack || defaultsEventsToTrack
  percentsPlayedInterval = options.percentsPlayedInterval || dataSetupOptions.percentsPlayedInterval || 10

  eventCategory = options.eventCategory || dataSetupOptions.eventCategory || 'Video'
  # if you didn't specify a name, it will be 'guessed' from the video src after metadatas are loaded
  eventLabel = options.eventLabel || dataSetupOptions.eventLabel

  # in case the ga variables are using a different key
  gaUniversalObject = options.gaUniversalObject || dataSetupOptions.gaUniversalObject || 'ga'
  gaClassicObject = options.gaClassicObject || dataSetupOptions.gaClassicObject || '_gaq'

  # if you need to specify the event sent for a certain tracking object
  gaUniversalTracker = '';
  if options.gaUniversalTracker
    gaUniversalTracker = options.gaUniversalTracker + '.'
  else if dataSetupOptions.gaUniversalTracker
    gaUniversalTracker = dataSetupOptions.gaUniversalTracker + '.'
  
  # init a few variables
  percentsAlreadyTracked = []
  secondsAlreadyTracked = []
  seekStart = seekEnd = 0
  seeking = false

  loaded = ->
    unless eventLabel
      eventLabel = @currentSrc().split("/").slice(-1)[0].replace(/\.(\w{3,4})(\?.*)?$/i,'')

    if "loaded" in eventsToTrack
      sendbeacon( 'loadedmetadata', true )

    return

  timeupdate = ->
    currentTime = Math.round(@currentTime())
    duration = Math.round(@duration())
    percentPlayed = Math.round(currentTime/duration*100)
    isPaused = @paused()

    # this is somewhat janky as it ignores seeking
    # it essentially is an indicator which ONLY tells how far someone ever got into a video, but not if they watched it completely up to that point
    # it does however nicely handle "start" event
    for percent in [0..99] by percentsPlayedInterval
      if percentPlayed >= percent && percent not in percentsAlreadyTracked

        if "start" in eventsToTrack && percent == 0 && percentPlayed > 0
          sendbeacon( 'start', true )
        else if "percentsPlayed" in eventsToTrack && percentPlayed != 0
          sendbeacon( 'percent played', true, percent )

        if percentPlayed > 0
          percentsAlreadyTracked.push(percent)

    # sometimes duration will be 0 on very first timeupdate call
    if "secondsPlayed" in eventsToTrack && currentTime not in secondsAlreadyTracked && duration && !isPaused && !seeking
      # handles the case if through the magic of slow js we missed the event of currentTime % secondsPlayedInterval == 0, and now we are X seconds beyond secondsPlayedInterval
      # we would still like to notify the seconds played (as we might miss the next secondsPlayedInterval as well)
      # if all things play nicely we should always see events happen at secondsPlayedInterval, if things don't play nicely we also cover that too
      # secondsPlayedInterval will be calculated from percentsPlayedInterval to be dynamic per video, as this will eventually lead us to hitting analytics.js limit
      secondsPlayedInterval = percentsPlayedInterval / 100.0 * duration
      lastSecond = if secondsAlreadyTracked.length > 0 then secondsAlreadyTracked[secondsAlreadyTracked.length-1] else 0
      timeDiff = currentTime - lastSecond
      if timeDiff >= secondsPlayedInterval
          sendbeacon( 'seconds played', true, timeDiff )
          secondsAlreadyTracked.push(currentTime)

    # we always start timestamps here to get used in seeking event
    seekStart = seekEnd
    seekEnd = currentTime

    return

  end = ->
    # send beacon for the final time segment
    currentTime = Math.round(@currentTime())
    if "secondsPlayed" in eventsToTrack && currentTime not in secondsAlreadyTracked
      lastSecond = if secondsAlreadyTracked.length > 0 then secondsAlreadyTracked[secondsAlreadyTracked.length-1] else 0
      timeDiff = currentTime - lastSecond
      if timeDiff > 0
        sendbeacon( 'seconds played', true, timeDiff )
        # because we are about to reset secondsAlreadyTracked we don't need to push in current time

    # reset values for seeking and secondsPlayed, pretend like its the first run of video
    secondsAlreadyTracked = []
    seekStart = seekEnd = 0
    seeking = false

    if "end" in eventsToTrack
      sendbeacon( 'end', true )
    return

  play = ->
    currentTime = Math.round(@currentTime())

    # play events are fired after seeking it seems?
    # so we can always reset our secondsAlreadyTracked here
    secondsAlreadyTracked = [currentTime]

    if "play" in eventsToTrack
      sendbeacon( 'play', true, currentTime )
    seeking = false
    return

  pause = ->
    currentTime = Math.round(@currentTime())
    duration = Math.round(@duration())

    # we also want to be sure to send the last segment's time played (if greater than 0) on pauses
    if "secondsPlayed" in eventsToTrack && currentTime not in secondsAlreadyTracked
      lastSecond = if secondsAlreadyTracked.length > 0 then secondsAlreadyTracked[secondsAlreadyTracked.length-1] else 0
      timeDiff = currentTime - lastSecond
      if timeDiff > 0
        sendbeacon( 'seconds played', true, timeDiff )
        secondsAlreadyTracked.push(currentTime)

    if "pause" in eventsToTrack && currentTime != duration && !seeking
      sendbeacon( 'pause', false, currentTime )
    return

  seeking = ->
    # called just prior to seek completion (seeked)
    # we want to always reset our seconds here
    currentTime = Math.round(@currentTime())
    isPaused = @paused()

    # remember seekStart/seekEnd will be swapped in updatetime when it gets called AFTER this
    # we just order them here to make sense of it
    _seekStart = seekEnd
    _seekEnd = currentTime

    # handle last watched segment prior to seek (similar to function to end)
    if "secondsPlayed" in eventsToTrack && currentTime not in secondsAlreadyTracked
      lastSecond = if secondsAlreadyTracked.length > 0 then secondsAlreadyTracked[secondsAlreadyTracked.length-1] else 0
      # _seekStart is our last known watched timestamp
      timeDiff = _seekStart - lastSecond
      if timeDiff > 0
        sendbeacon( 'seconds played', true, timeDiff )
        # because we are about to reset secondsAlreadyTracked we don't need to push in current time

    # if the difference between the start and the end are greater than 1 it's a seek.
    if Math.abs(_seekStart - _seekEnd) > 1
      seeking = true
      if "seek" in eventsToTrack
        sendbeacon( 'seek start', false, _seekStart )
        sendbeacon( 'seek end', false, _seekEnd )

    # reset to our new starting point, currentTime
    secondsAlreadyTracked = [currentTime]
    return

  # value between 0 (muted) and 1
  volumeChange = ->
    volume = if @muted() == true then 0 else @volume()
    sendbeacon( 'volume change', false, volume )
    return

  resize = ->
    sendbeacon( 'resize - ' + @width() + "*" + @height(), true )
    return

  error = ->
    currentTime = Math.round(@currentTime())
    # XXX: Is there some informations about the error somewhere ?
    sendbeacon( 'error', true, currentTime )
    return

  fullscreen = ->
    currentTime = Math.round(@currentTime())
    if @isFullscreen?() || @isFullScreen?()
      sendbeacon( 'enter fullscreen', false, currentTime )
    else
      sendbeacon( 'exit fullscreen', false, currentTime )
    return

  sendbeacon = ( action, nonInteraction, value ) ->
    # console.log action, " ", nonInteraction, " ", value
    if window[gaUniversalObject]
      window[gaUniversalObject] (gaUniversalTracker + 'send'), 'event',
        'eventCategory' 	: eventCategory
        'eventAction'		  : action
        'eventLabel'		  : eventLabel
        'eventValue'      : value
        'nonInteraction'	: nonInteraction
    else if window[gaClassicObject]
      window[gaClassicObject].push(['_trackEvent', eventCategory, action, eventLabel, value, nonInteraction])
    else
      console.log("Google Analytics not detected")
    return

  @ready ->
    @on("loadedmetadata", loaded)
    @on("timeupdate", timeupdate)
    @on("ended", end)
    @on("play", play)
    @on("pause", pause) if "pause" in eventsToTrack || "secondsPlayed" in eventsToTrack
    @on("seeking", seeking)
    @on("volumechange", volumeChange) if "volumeChange" in eventsToTrack
    @on("resize", resize) if "resize" in eventsToTrack
    @on("error", error) if "error" in eventsToTrack
    @on("fullscreenchange", fullscreen) if "fullscreen" in eventsToTrack
  return
