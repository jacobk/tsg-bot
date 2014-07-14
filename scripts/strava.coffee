# Description:
#   Strava stuff
#
# Commands:
#   strava auth <athlete id> - Authorizes bot to access strava acitivity details
#
# Author:
#   jacobk
#
# TODO:
# * alias with irc nicks

_ = require "underscore"
scopedClient = require 'scoped-http-client'
moment = require "moment"
RSVP = require "rsvp"
querystring = require "querystring"
request = require "request"

Hipchat = require('../lib/hipchat')

strava_access_token  = process.env.STRAVA_ACCESS_TOKEN
strava_client_id     = process.env.STRAVA_CLIENT_ID
strava_client_secret = process.env.STRAVA_CLIENT_SECRET
strava_club_id       = process.env.STRAVA_CLUB_ID
strava_announce_room = process.env.STRAVA_ROOM || "#tsg"
strava_poll_freq     = process.env.STRAVA_POLL_RATE || 60000
strava_callback_url  = process.env.STRAVA_CALLBACK_URL || "http://tsg.herokuapp.com/hubot/strava/token_exchange"
bitly_access_token   = process.env.BITLY_ACCESS_TOKEN

STRAVA_EVT_TOKEN = "strava:tokenCreated"

module.exports = (robot) ->

  hipchat = new Hipchat(robot)
  auth = new Auth(strava_client_id, strava_client_secret, strava_callback_url, robot)

  robot.brain.on "loaded", ->
    robot.brain.data.strava ?=
      lastActivityId: 0
      athletes: {}
    poller = new StravaClubPoller(strava_club_id, strava_access_token, strava_announce_room, robot, hipchat)
    setInterval =>
      poller.poll()
    , strava_poll_freq

  robot.router.get '/hubot/strava/token_exchange', (req, res) ->
    # state is ahtleteId
    {state, code} = querystring.parse(req._parsedUrl.query)
    robot.logger.debug "Got authorization from #{state} code #{code}"

    res.setHeader 'Content-Type', 'text/html'
    auth.requestToken(state, code)
      .then (athlete) ->
        res.end "Created token"
      .catch (reason) ->
        res.end "Failed to create token #{JSON.stringify reason}"

  # auth <athlete id>
  robot.respond /strava auth (\S+)/i, (msg) ->
    athleteId = msg.match[1]
    msg.reply auth.authorizeUrl athleteId


class Auth

  constructor: (@clientId, @clientSecret, @callbackUrl, @robot) ->

  # TODO
  verifyAtheleteId: (athleteId) ->
    # Accept all ids for now
    new RSVP.resolve()

  authorizeUrl: (athleteId) ->
    "https://www.strava.com/oauth/authorize?"+
      "client_id=#{@clientId}"+
      "&response_type=code"+
      "&redirect_uri=#{ encodeURIComponent @callbackUrl }"+
      "&state=#{ athleteId }"+
      "&approval_prompt=auto"

  requestToken: (athleteId, code) ->
    @robot.logger.debug "Requesting token #{athleteId} #{code}"
    new RSVP.Promise (resolve, reject) =>
      request {
        method: "POST"
        uri: "https://www.strava.com/oauth/token"
        qs:
          client_id: @clientId
          client_secret: @clientSecret
          code: code
      }, (error, response, body) =>
          if error or response.statusCode isnt 200
            @robot.logger.debug body
            @robot.logger.error 'Failed to create token'
            reject error: error, body: body
          else
            {access_token, athlete} = JSON.parse body
            @robot.logger.debug "Got token data: #{body}"
            @robot.logger.info "Created token for #{athlete.firstname}"
            @storeToken access_token, athlete
            resolve athlete

  storeToken: (token, athlete) ->
    @robot.logger.debug "Storing athlete token"
    @robot.brain.data.strava.athletes ?= {}
    @robot.brain.data.strava.athletes[athlete.id] =
      token: token
      details: athlete
    @robot.brain.save()


# Assume monotonically increasing strava activity ids
class StravaClubPoller

  constructor: (clubId, accessToken, room, robot, hipchat) ->
    @clubId      = clubId
    @accessToken = accessToken
    @room        = room
    @robot       = robot
    @hipchat     = hipchat
    @buildClient()
    @bitlyClient = new BitlyClient(bitly_access_token)

  poll: ->
    @robot.logger.debug "Polling Strava.com"
    @client.get() (err, resp, body) =>
      @robot.logger.error "Failed to poll Strava.com" unless resp.statusCode is 200
      data = JSON.parse(body)
      @handleStravaResponse data

  handleStravaResponse: (data) ->
    newActivities = @findNewActivities data
    unless _.isEmpty(newActivities)
      @announce activity for activity in newActivities
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
    @robot.logger.debug "Updating cursor. New cursor: #{newCursor}"
    @robot.brain.data.strava.lastActivityId = newCursor
    @robot.brain.save()

  announce: (activity) ->
    @bitlyClient.shorten @activityUrl(activity), (shortUrl) =>
      params =
        room: @room
        from: 'Strava'
        format: 'html'
        color: 'yellow'
        message: @formatActivity(activity, shortUrl)
      @hipchat.postMessage params

  formatActivity: (activity, shortUrl) ->
    athlete = activity.athlete
    fullName = "#{athlete.firstname} #{athlete.lastname}"
    verb = {"Run": "ran", "Ride": "rode"}[activity.type]
    distance = (activity.distance / 1000.0).toFixed(1)
    duration = moment.utc(activity.moving_time*1000).format("HH:mm:ss")
    avg_speed = activity.distance / activity.moving_time
    pace = 1000 / (avg_speed * 60)
    pace_min = Math.floor(pace)
    pace_secs = ((pace - pace_min) * 60).toFixed(0)
    pace_secs = "0#{pace_secs}" if pace_secs < 10
    pace = "#{pace_min}:#{pace_secs}"
    "New activity \"#{activity.name}\": " +
      "<b>#{fullName}</b> <i>#{verb}</i> <b>#{distance}</b> km in #{duration} <i>(#{pace} min/km)</i> " +
      "near #{activity.location_city}, #{activity.location_country} #{shortUrl}"

  activityUrl: (activity) ->
    "http://www.strava.com/activities/#{activity.id}"

  buildClient: ->
    @client = scopedClient.create(@url())

  url: ->
   "https://www.strava.com/api/v3/clubs/#{@clubId}/activities?access_token=#{@accessToken}"

class BitlyClient

  @BASE_URL = "https://api-ssl.bitly.com"

  constructor: (accessToken) ->
    @accessToken = accessToken

  shorten: (url, cb) ->
    options =
      access_token: @accessToken
      domain: "j.mp"
      longUrl: url
    client = scopedClient.create(BitlyClient.BASE_URL)
      .path("/v3/shorten")
      .query(options)
      .get() (err, resp, body) =>
        unless resp.statusCode is 200
          @robot.logger.error "Failed to shorten url with bitly"
          cb(url)
        else
          data = JSON.parse(body)
          if data.status_code is 200 then cb(data.data.url) else cb(url)

