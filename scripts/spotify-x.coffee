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
        type = data.info.type
        if type in ["track", "album", "artist"]
          last_fm.getPlayCounts type, msg, data

  robot.respond /lastfm alias (\S+) (\S+)/i, (msg) ->
    lastfm      = robot.brain.data.lastfm ?= {}
    lastfm_name = msg.match[1]
    alias       = msg.match[2]

    lastfm[lastfm_name] = alias
    msg.reply "#{lastfm_name} will henceforth be known as #{alias}. " +
              "Remove alias with 'lastfm clear <last.fm-user>'"

  robot.respond /lastfm clear (\S+)/i, (msg) ->
    lastfm      = robot.brain.data.lastfm ?= {}
    lastfm_name = msg.match[1]
    if lastfm_name of lastfm
      delete lastfm[lastfm_name]
      msg.reply "Alias removed for #{lastfm_name}"
    else
      msg.reply "No alias for #{lastfm_name}. Try 'lastfm alias <last.fm-user>'"

  robot.respond /lastfm list/i, (msg) ->
    aliases = ("#{u}->#{a}" for u, a of robot.brain.data.lastfm ?= {})
    msg.reply "Last.fm aliases: #{aliases.join ', '}"


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




class LastFm

  @BASE_URL = "http://ws.audioscrobbler.com/2.0/"

  constructor: (key, groups, robot) ->
    @key    = key
    @robot  = robot
    @buildClient()
    @getGroupMembers groups.split(/\s*,\s*/), (members) =>
      @users = members

  getPlayCounts: (type, msg, data) ->
    options = method: "#{type}.getInfo"

    if type is "track"
      options.artist = data.track.artists[0].name
      options.track  = data.track.name
    else if type is "album"
      options.artist = data.album.artist
      options.album  = data.album.name
    else if type is "artist"
      options.artist = data.artist.name

    counts = deferred.map @users, (user) =>
      @getPlayCount(type, options, user)
    counts.then(
      ((result) =>
        listeners = (user for user in result when user.count > 0)
        if listeners.length > 0
          listeners = ("#{@getAlias user.user}(#{user.count})" for user in listeners)
          msg.send "Listeners: #{listeners.join(", ")}"
      ),
      ((err) ->
        console.log "ERR", err
      )
    )

  getPlayCount: (type, options, user) ->
    def = deferred()
    options.username = user
    @client.scope().query(options).get() (err, resp, body) =>
      data = JSON.parse body
      unless data.error
        if type == "artist"
          def.resolve {user: user, count: data[type].stats.userplaycount}
        else
          def.resolve {user: user, count: data[type].userplaycount}
      else
        console.log "Last.fm failure", body
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

  getAlias: (user) ->
    @robot.brain.data.lastfm[user] ? user

  buildClient: ->
    options =
      api_key: @key
      format: "json"
    @client = @robot.http(LastFm.BASE_URL).query(options)
