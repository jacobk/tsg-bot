# Description:
#   Strava stuff
#
# Commands:
#   strava auth - Authorizes bot to access strava activity details
#   strava show <athlete id> <activity id> - Show info for provided activity
#
# Author:
#   jacobk
#
# TODO:
# * alias with irc nicks

_ = require "lodash"
scopedClient = require 'scoped-http-client'
moment = require "moment"
RSVP = require "rsvp"
querystring = require "querystring"
request = require "request"
ss = require "simple-statistics"
sprintf = require("sprintf-js").sprintf

Hipchat = require('../lib/hipchat')

# CONFIGURATION
#

strava_access_token  = process.env.STRAVA_ACCESS_TOKEN
strava_client_id     = process.env.STRAVA_CLIENT_ID
strava_client_secret = process.env.STRAVA_CLIENT_SECRET
strava_club_id       = process.env.STRAVA_CLUB_ID
strava_announce_room = process.env.STRAVA_ROOM || "#tsg"
strava_poll_freq     = process.env.STRAVA_POLL_RATE || 60000
strava_callback_url  = process.env.STRAVA_CALLBACK_URL || "http://tsg.herokuapp.com/hubot/strava/token_exchange"
bitly_access_token   = process.env.BITLY_ACCESS_TOKEN


# EVENT DECLARATIONS
#

STRAVA_EVT_NEWTOKEN = "strava:tokenCreated"
STRAVA_EVT_NOTOKEN = "strava:noToken"
STRAVA_EVT_NEWACTIVITY = "strava:newActivity"

module.exports = (robot) ->

  hipchat = new Hipchat(robot)
  store = new Store(robot)
  api = new APIv3(strava_client_id, strava_client_secret, store, robot)
  auth = new Auth(strava_callback_url, api, store, robot)
  poller = new StravaClubPoller(strava_club_id, strava_access_token, strava_announce_room, robot, hipchat)


  # HELPERS
  #

  hc_params = (message) ->
    room: strava_announce_room
    from: "Strava"
    message: message
    format: "html"
    color: "yellow"

  send = (message) ->
    hipchat.postMessage hc_params message

  sendDelayed = (message) ->
    process.nextTick -> hipchat.postMessage hc_params message

  announceActivity = (activity) -> send activity.formatHTML()


  # GLOBAL EVENT HANDLING
  #

  robot.brain.on "loaded", ->
    robot.logger.info "Initiating Strava.com poller"
    robot.brain.data.strava ?=
      lastActivityId: 0
      athletes: {}
    setInterval =>
      poller.poll()
    , strava_poll_freq


  # STRAVA SPECIFIC EVENT HANDLING
  #

  robot.on STRAVA_EVT_NEWACTIVITY, (activityData, additionalActivites=[]) ->
    activity = Activity.createFromData activityData, api, robot
    robot.logger.info "Handling new activity event. #{activity}"
    activity.load()
      .then(announceActivity, announceActivity)
      .then ->
        unless _.isEmpty additionalActivites
          additionalAthletes = _.chain(additionalActivites)
            .map (ad) ->
              Activity.createFromData(ad, api, robot).fullName()
            .uniq()
            .join(", ")
            .value()

          send """Found #{additionalActivites.length} additional activites
               from <i>#{additionalAthletes}</i>
               check them out at
               <a href='http://www.strava.com/clubs/#{strava_club_id}/recent_activity'>
               the club page</a>"""
      .catch (reason) ->
        robot.logger.error "Faliled to handle new activity", reason.stack

  robot.on STRAVA_EVT_NOTOKEN, (athleteId, activityId) ->
    message = "Athlete hasn't authorized me to show more details :( " +
              "Tell hen to click <a href='#{auth.authorizeUrl(activityId)}'>" +
              "this link</a>"
    sendDelayed message

  robot.on STRAVA_EVT_NEWTOKEN, (token, athlete) ->
    message = "Access token added for " +
              "<b>#{athlete.firstname} #{athlete.lastname}</b>"
    send message


  # TRIGGERS
  #

  robot.hear /strava cursor (\d+)/, (msg) ->
    cursor = msg.match[1]
    poller.setCursor cursor

  robot.hear /strava token clear (\d+)/, (msg) ->
    athleteId = msg.match[1]
    store.deleteToken athleteId

  robot.hear /strava fake( \d+)?/, (msg) ->
    url = "https://www.strava.com/api/v3/clubs/#{strava_club_id}/activities?access_token=#{strava_access_token}&per_page=20"
    idx = parseInt((msg.match[1] || 0), 10)
    request url, (err, res, body) =>
      data = JSON.parse(body)
      console.dir _.map data, (a) -> a.athlete.id
      robot.emit STRAVA_EVT_NEWACTIVITY, data[idx]

  robot.respond /strava auth/i, (msg) ->
    msg.send "Click this link:  #{auth.authorizeUrl()}"

  robot.respond /strava show (\S+) (\S+)/i, (msg) ->
    athleteId  = msg.match[1]
    activityId = msg.match[2]
    activity   = new Activity athleteId, activityId, api, robot
    activity.load().then(announceActivity, announceActivity)

  robot.router.get '/hubot/strava/token_exchange', (req, res) ->
    {code, state} = querystring.parse(req._parsedUrl.query)
    robot.logger.debug "Got authorization from  with code #{code}"

    res.setHeader 'Content-Type', 'text/html'
    auth.requestToken(code)
      .then (athlete) ->
        # state (state = activityId) is available if the auth seq was initiated
        # after a failed attempt to show an activity with full details.
        if state
          robot.logger.debug "Token exchange state found #{state} will pair " +
                             "with athlete #{JSON.stringify athlete}"
          api.activity(athlete.id, state).then (activity) ->
            robot.logger.debug "State triggered activity loaded #{activity} " +
                               "Will emit STRAVA_EVT_NEWACTIVITY event."
            robot.emit STRAVA_EVT_NEWACTIVITY, activity
        res.end "Created token"
      .catch (reason) ->
        res.end "Failed to create token #{JSON.stringify reason}"


# CLASSES
#

class NoTokenError extends Error
  constructor: -> super


class Activity
  constructor: (@athleteId, @activityId, @api, @robot, @data) ->
    @athlete = @data.athlete if @data?.athlete?.resource_state > 1

  @createFromData: (data, api, robot) ->
    new Activity data.athlete.id, data.id, api, robot, data

  isDetailed: -> @data?.resource_state is 3
  hasData: -> @data?

  # Series type base always available if streams
  hasStreams: -> @streams?.length > 1

  load: ->
    @robot.logger.info "Loading #{@}"
    streams = ["altitude", "velocity_smooth", "heartrate", "cadence", "temp",
               "grade_smooth"]
    RSVP.hash
      activity: @api.activity(@athleteId, @activityId)
      streams: @api.streams(@athleteId, @activityId, streams...)
      athlete: @athlete || @api.athleteSummary(@athleteId)
    .then (data) =>
      @data = data.activity
      @streams = data.streams
      @athlete = data.athlete
      @
    .catch (reason) =>
      @robot.logger.info "Failed to load #{@}"
      if reason instanceof NoTokenError
        @robot.emit(STRAVA_EVT_NOTOKEN, @athleteId, @activityId)
      @

  formatHTML: ->
    return 'N/A' unless @hasData()
    message = """
              New activity <a href='#{@url()}'>\"#{@data.name}\"</a>:
              <b>#{@fullName()}</b>
              <i>#{@_verb()}</i>
              <b>#{@distance()}</b> km in #{@duration()}
              <i>(#{@_velocityString()}, #{@elevationGain()} m, #{@avgHeartrate()} bpm)</i>
              near #{@data.location_city}
              """
    message += @formatStreamsHTML() if @hasStreams()
    message

  formatStreamsHTML: ->
    rows = _.chain(@streams)
      .reject(type: "distance")
      .map (stream) =>
        cells = _.map @_streamStats(stream), (stat) -> "<td>#{stat}</td>"
        "<tr>#{cells.join('')}</tr>"
      .join("\n")
      .value()
    "<table>
      <thead>
        <tr>
          <th>Stream</th>
          <th>Mean</th>
          <th>Stddev</th>
          <th>Min</th>
          <th>Q1</th>
          <th>Median</th>
          <th>Q3</th>
          <th>Max</th>
        </tr>
      </thead>
      <tbody>
        #{rows}
      </tbody>
    </table>"


  distance: -> (@data.distance / 1000.0).toFixed(1)

  duration: -> moment.utc(@data.moving_time*1000).format("HH:mm:ss")

  fullName: -> "#{@athlete.firstname} #{@athlete.lastname}"

  avgSpeedMPS: -> @data.distance / @data.moving_time

  avgSpeedKMPH: -> @_mpsTokmph @avgSpeedMPS()

  avgPace: -> @_speedToPaceString @avgSpeedMPS()

  avgHeartrate: -> @data.average_heartrate or "-"

  elevationGain: -> @data.total_elevation_gain

  url: ->
    "http://www.strava.com/activities/#{@data.id}"

  toString: ->
    "Acitivy: athlete: #{@athleteId} activity: #{@activityId} (data: #{@hasData()} detailed: #{@isDetailed()})"

  # PRIVATE
  #

  _streamStats: (stream) ->
    # Type, Mean, Stddev, Min, Q1, Median, Q4, Max,
    data = stream.data

    # Pre-convert to pace when needed to make sane stddev for pace
    if stream.type is "velocity_smooth" and @_preferPace()
      data = _.map data, (value) => @_speedToPace value

    stats = [
      ss.mean(data),
      ss.standard_deviation(data),
      ss.min(data),
      ss.quantile(data, 0.25),
      ss.median(data),
      ss.quantile(data, 0.75),
      ss.max(data)
    ]

    if stream.type is "velocity_smooth"
      stats = _.map stats, (value) =>
        if @_preferPace() then @_paceString(value) else @_mpsTokmph(value)

    stats = _.map stats, (stat) ->
      if _.isNumber stat then stat.toFixed(1) else stat

    stats.unshift @_streamLegend(stream.type)
    stats

  _velocityString: ->
    if @_preferPace()
      "#{@avgPace()} min/km"
    else
      "#{@avgSpeedKMPH().toFixed(1)} km/h"

  _paceString: (pace) ->
    pace_min = Math.floor(pace)
    pace_secs = (pace - pace_min) * 60
    sprintf "%d:%02d", pace_min, pace_secs

  _preferPace: ->
    paced = ["Run", "Swim", "Hike", "Walk", "Snowshoe"]
    @data.type in paced

  _streamLegend: (type) ->
    types =
      altitude: "Elevation (m)"
      velocity_smooth: if @_preferPace() then "Pace (min/km)" else "Speed (km/h)"
      heartrate: "Heartreate (bpm)"
      cadence: "Cadence (rpm)"
      temp: "Temp (C)"
      grade_smooth: "Grade (%)"
    types[type]

  _verb: ->
    types =
      Ride: "rode"
      Run: "ran"
      Swim : "swam"
      Hike: "hiked"
      Walk: "walked"
      NordicSki: "skied"
      AlpineSki: "skied"
      BackcountrySki: "skied"
      IceSkate: "ice skated"
      InlineSkate: "inlined"
      Kitesurf: "kite surfed"
      RollerSki: "roller skied"
      Windsurf: "windsurfed"
      Workout: "worked out"
      Snowboard: "snoboarded"
      Snowshoe: "snow shoed"
    types[@data.type]

  _mpsTokmph: (speed) ->
    speed * 3600.0 / 1000.0

  _speedToPace: (speed) ->
    if speed is 0 then 0 else 1000 / (speed * 60)

  _speedToPaceString: (speed) ->
    @_paceString @_speedToPace(speed)


class Store
  constructor: (@robot) ->

  storeToken: (token, athlete) ->
    @robot.logger.debug "Storing athlete token"
    @robot.brain.data.strava.athletes ?= {}
    @robot.brain.data.strava.athletes[athlete.id] =
      token: token
      details: athlete
    @robot.brain.save()
    @robot.emit STRAVA_EVT_NEWTOKEN, token, athlete

  deleteToken: (athleteId) ->
    @robot.logger.debug  "Deleting strava token for #{athleteId}"
    delete @robot.brain.data.strava.athletes[athleteId]
    @robot.brain.save()

  loadToken: (athleteId) ->
    @robot.logger.info "Loading token for #{athleteId}"
    athlete = @robot.brain.data.strava.athletes[athleteId]
    new RSVP.Promise (resolve, reject) =>
      unless athlete
        msg = "Couldn't find strava token for #{athleteId}"
        @robot.logger.info msg
        reject new NoTokenError msg
      else
        @robot.logger.debug "Found athlete with token #{athlete.token}"
        resolve athlete.token


class Auth

  constructor: (@callbackUrl, @api, @store, @robot) ->

  authorizeUrl: (activityId) ->
    url = "https://www.strava.com/oauth/authorize?"+
      "client_id=#{@api.clientId}"+
      "&response_type=code"+
      "&redirect_uri=#{ encodeURIComponent @callbackUrl }"+
      "&approval_prompt=auto"
    url += "&state=#{activityId}" if activityId

  requestToken: (code) ->
    @robot.logger.debug "Requesting token #{code}"
    return @api.requestToken(code).then (res) =>
      {token, athlete} = res
      @store.storeToken token, athlete
      athlete


class APIv3

  @BASE_URL = "https://www.strava.com/api/v3"

  constructor: (@clientId, @clientSecret, @store, @robot) ->

  # AUTH
  #

  requestToken: (code) ->
    @robot.logger.debug "Requesting token #{code}"
    @_apiRequest('', {
      method: "POST"
      uri: "https://www.strava.com/oauth/token" # Not api v3 base url
      qs:
        client_id: @clientId
        client_secret: @clientSecret
        code: code
      }).then (data) =>
        {access_token, athlete} = data
        @robot.logger.info "Created token for #{athlete.firstname} #{athlete.lastname}"
        return token: access_token, athlete: athlete

  # ATHLETES
  #

  athleteSummary: (athleteId) ->
    endpoint = "/athletes/#{athleteId}"
    @_authenticatedRequest athleteId, endpoint


  # ACTIVITIES
  #

  activity: (athleteId, activityId) ->
    endpoint = "/activities/#{activityId}"
    @_authenticatedRequest athleteId, endpoint


  # STREAMS
  #

  streams: (athleteId, activityId, streams...) ->
    # time: integer seconds
    # altitude: float meters
    # velocity_smooth:  float meters per second
    # heartrate:  integer BPM
    # cadence:  integer RPM
    # temp: integer degrees Celsius
    # grade_smooth: float percent
    endpoint = "/activities/#{activityId}/streams/#{streams.join(',')}"
    @_authenticatedRequest athleteId, endpoint


  # PRIVATE
  #

  _authenticatedRequest: (athleteId, endpoint, options={}) ->
    @robot.logger.info "Performing authenticated request for athlete: #{athleteId}" +
                       " to endpoit #{endpoint}"
    # -H "Authorization: Bearer 83ebeabdec09f6670863766f792ead24d61fe3f9"
    @store.loadToken(athleteId)
      .then (token) =>
        @robot.logger.debug "Found Strava token for #{athleteId} => #{token}"
        defaultOptions =
          headers:
            "Authorization": "Bearer #{token}"
        _.defaults options, defaultOptions
        @_apiRequest endpoint, options
      # .catch (reason) =>



  _apiRequest: (endpoint, options={}) ->
    new RSVP.Promise (resolve, reject) =>
      defaultOptions =
        method: "GET"
        uri: "#{APIv3.BASE_URL}#{endpoint}"
      _.defaults options, defaultOptions
      request options, (error, response, body) =>
        # Don't support redirects
        @robot.logger.debug "Strava API response (code: #{response.statusCode})"
        if error or response.statusCode < 200 or response.statusCode >= 300
          @robot.logger.debug body
          @robot.logger.error 'API request failed'
          reject error: error, body: body
        else
          # @robot.logger.debug "Got data: #{body}"
          resolve JSON.parse body


# Assume monotonically increasing strava activity ids
class StravaClubPoller

  constructor: (clubId, accessToken, room, robot, hipchat) ->
    @clubId      = clubId
    @accessToken = accessToken
    @room        = room
    @robot       = robot
    @hipchat     = hipchat
    @buildClient()

  poll: ->
    @robot.logger.debug "Polling Strava.com"
    @client.get() (err, resp, body) =>
      if resp.statusCode is 200
        data = JSON.parse(body)
        @handleStravaResponse data
      else
        @robot.logger.error "Failed to poll Strava.com:
                              status: #{resp.statusCode}
                              body: #{body}"

  handleStravaResponse: (data) ->
    newActivities = @findNewActivities data
    unless _.isEmpty(newActivities)
      [first, rest...] = newActivities
      @robot.emit STRAVA_EVT_NEWACTIVITY, first, rest
      @updateCursor newActivities
    else
      @robot.logger.debug "No new Strava activities"

  findNewActivities: (data) ->
    @robot.logger.debug "Looking for new activities (cursor: #{@currentCursor()})"
    _.filter data, (activity) => activity.id > @currentCursor()

  currentCursor: ->
    @robot.brain.data.strava.lastActivityId

  updateCursor: (activities) ->
    newCursor = _.first(activities).id
    @setCursor newCursor

  setCursor: (newCursor) ->
    @robot.logger.debug "Updating cursor. New cursor: #{newCursor}"
    @robot.brain.data.strava.lastActivityId = newCursor
    @robot.brain.save()

  buildClient: ->
    @client = scopedClient.create(@url())

  url: ->
   "https://www.strava.com/api/v3/clubs/#{@clubId}/activities?access_token=#{@accessToken}"