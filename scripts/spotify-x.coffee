# Description:
#   Metadata lookup for spotify links
#
# Dependencies:
#   None
#
# Configuration:
#   None
#
# Commands:
#   <spotify link> - returns info about the link (track, artist, etc.)
#
# Author:
#   jacobk

deferred = require "deferred"

lastfm_key    = process.env.LAST_FM_KEY
lastfm_groups = process.env.LAST_FM_GROUPS || "tsg"

module.exports = (robot) ->

  last_fm = new LastFm lastfm_key, lastfm_groups, robot

  robot.hear spotify.link, (msg) ->
    msg.http(spotify.uri msg.match[0]).get() (err, res, body) ->
      if res.statusCode is 200
        data = JSON.parse(body)
        msg.send spotify[data.info.type](data)
        if data.info.type is "track"
          last_fm.getPlayCounts msg, data

spotify =
  link: /// (
    ?: http://open.spotify.com/(track|album|artist)/
     | spotify:(track|album|artist):
    ) \S+ ///

  uri: (link) -> "http://ws.spotify.com/lookup/1/.json?uri=#{link}"

  track: (data) ->
    track = "#{data.track.artists[0].name} - #{data.track.name}"
    album = "(#{data.track.album.name}) (#{data.track.album.released})"
    "Track: #{track} #{album}"

  album: (data) ->
    "Album: #{data.album.artist} - #{data.album.name} (#{data.album.released})"

  artist: (data) ->
    "Artist: #{data.artist.name}"

lastfm =
  track: (data) ->
    artist = data.track.artists[0].name
    track  = data.track.name



class LastFm

  @BASE_URL = "http://ws.audioscrobbler.com/2.0/"

  constructor: (key, groups, robot) ->
    @key    = key
    @robot  = robot
    @buildClient()
    @getGroupMembers groups.split(/\s*,\s*/), (members) =>
      @users = members

  getPlayCounts: (msg, data) ->
    artist = data.track.artists[0].name
    track  = data.track.name
    counts = deferred.map @users, (user) =>
      @getPlayCount(artist, track, user)
    counts.then(
      ((result) ->
        listeners = (user for user in result when user.count > 0)
        if listeners.length > 0
          listeners = ("#{user.user}(#{user.count})" for user in listeners)
          msg.send "Listeners: #{listeners.join(", ")}"
      ),
      ((err) ->
        console.log "ERR", err
      )
    )


  getPlayCount: (artist, track, user) ->
    def = deferred()
    options =
      method: "track.getInfo"
      artist: artist
      track: track
      username: user

    @client.scope().query(options).get() (err, resp, body) =>
      data = JSON.parse body
      unless data.error
        def.resolve {user: user, count: data.track.userplaycount}
      else
        def.resolve new Error("Failed to get playcount")

    def.promise

  getGroupMembers: (groups, callback) ->
    console.log "Last.fm getting members for groups #{groups}"
    members = {}
    for group in groups
      options =
        method: "group.getmembers"
        group: group
      @client.scope().query(options).get() (err, resp, body) =>
        data = JSON.parse(body)
        for user in data.members.user
          members[user.name] = true
        callback(key for key, foo of members)


  buildClient: ->
    options =
      api_key: @key
      format: "json"
    @client = @robot.http(LastFm.BASE_URL).query(options)
