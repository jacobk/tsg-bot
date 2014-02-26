# Description:
#   Strava stuff
#
#
# Commands:
#   hubot link me <link id> - Posts link with that id from the link archive
#   hubot links - Provides a link to the links archive page
#
# Author:
#   jacobk

# TODO
# * alias with irc nicks

_ = require "underscore"
scopedClient = require 'scoped-http-client'
moment = require "moment"

strava_access_token  = process.env.STRAVA_ACCESS_TOKEN
strava_club_id       = process.env.STRAVA_CLUB_ID
strava_announce_room = process.env.STRAVA_ROOM || "#tsg"
strava_poll_freq     = process.env.STRAVA_POLL_RATE || 60000

module.exports = (robot) ->

  robot.brain.on "loaded", ->
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

  poll: ->
    @robot.logger.debug "Polling Strava.com"
    @client.get() (err, resp, body) =>
      console.error "Failed to poll Strava.com" unless resp.statusCode is 200
      @robot.logger.debug "Handling response: #{body}"
      data = JSON.parse(body)
      @handleStravaResponse data

  handleStravaResponse: (data) ->
    newActivities = @findNewActivities data
    @announce activity for activity in newActivities

  findNewActivities: (data) ->
    @robot.logger.debug "Looking for new activities (cursor: #{@currentCursor()})"
    _.filter data, (activity) => activity.id > @currentCursor()

  currentCursor: ->
    @robot.brain.data.strava.lastActivityId

  updateCursor: (activities) ->
    @robot.brain.data.strava.lastActivityId = _.last(activities).id

  announce: (activity) ->
    @robot.messageRoom @room, @formatActivity(activity)

  formatActivity: (activity) ->
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
    "New Strava.com activiy: #{fullName} #{verb} #{distance}km in #{duration} (#{pace} min/km)"

  buildClient: ->
    @client = scopedClient.create(@url())

  url: ->
   "https://www.strava.com/api/v3/clubs/#{@clubId}/activities?per_page=10&access_token=#{@accessToken}"