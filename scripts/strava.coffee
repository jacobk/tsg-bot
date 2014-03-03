# Description:
#   Strava stuff
#
# Author:
#   jacobk
#
# TODO:
# * alias with irc nicks

_ = require "underscore"
scopedClient = require 'scoped-http-client'
moment = require "moment"

strava_access_token  = process.env.STRAVA_ACCESS_TOKEN
strava_club_id       = process.env.STRAVA_CLUB_ID
strava_announce_room = process.env.STRAVA_ROOM || "#tsg"
strava_poll_freq     = process.env.STRAVA_POLL_RATE || 60000
bitly_access_token   = process.env.BITLY_ACCESS_TOKEN

module.exports = (robot) ->

  robot.brain.on "loaded", ->
    robot.logger.debug "Brain loaded in strava script", strava_poll_freq
    robot.logger.debug strava_poll_freq
    robot.brain.data.strava ?=
      lastActivityId: 0
    poller = new StravaClubPoller(strava_club_id, strava_access_token, strava_announce_room, robot)
    setInterval =>
      poller.poll()
    , strava_poll_freq


# Assume monotonically increasing strava activity ids
class StravaClubPoller

  constructor: (clubId, accessToken, room, robot) ->
    @clubId      = clubId
    @accessToken = accessToken
    @room        = room
    @robot       = robot
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
      @robot.messageRoom @room, @formatActivity(activity, shortUrl)

  formatActivity: (activity, shortUrl) ->
    athlete = activity.athlete
    fullName = "#{athlete.firstname} #{athlete.lastname}"
    verb = {"Run": "ran", "Ride": "rode"}[activity.type]
    distance = (activity.distance / 1000.0).toFixed(2)
    duration = moment.utc(activity.moving_time*1000).format("HH:mm:ss")
    avg_speed = activity.distance / activity.moving_time
    pace = 1000 / (avg_speed * 60)
    pace_min = Math.floor(pace)
    pace_secs = ((pace - pace_min) * 60).toFixed(0)
    pace = "#{pace_min}:#{pace_secs}"
    "New strava activity \"#{activity.name}\": " +
      "#{fullName} #{verb} #{distance} km in #{duration} (#{pace} min/km) " +
      "near #{activity.location_city}, #{activity.location_state}, #{activity.location_country} #{shortUrl}"

  activityUrl: (activity) ->
    "http://www.strava.com/activities/#{activity.id}"

  # shortenUrl: (url) ->
  #   bitly_url


  buildClient: ->
    @client = scopedClient.create(@url())

  url: ->
   "https://www.strava.com/api/v3/clubs/#{@clubId}/activities?per_page=10&access_token=#{@accessToken}"

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

