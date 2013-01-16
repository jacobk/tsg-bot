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
#   lastfm alias <lastfm username> <alias> - Creates and alias to beused in place of real nick
#   lastfm clear <lastfm username> - Removes alias
#   lastfm list - List all established aliases
#   lastfm last <lastfm user> - List all established aliases
#   <spotify link> - returns info about the link (track, artist, etc.)
#
# Author:
#   jacobk

deferred = require "deferred"
_ = require "underscore"
moment = require "moment"

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
              "Remove alias with 'lastfm clear #{alias}'"

  robot.respond /lastfm clear (\S+)/i, (msg) ->
    lastfm      = robot.brain.data.lastfm ?= {}
    lastfm_name = msg.match[1]
    if lastfm_name of lastfm
      delete lastfm[lastfm_name]
      msg.reply "Alias removed for #{lastfm_name}"
    else
      msg.reply "No alias for #{lastfm_name}."

  robot.respond /lastfm list/i, (msg) ->
    aliases = ("#{u}->#{a}" for u, a of robot.brain.data.lastfm ?= {})
    msg.reply "Last.fm aliases: #{aliases.join ', '}"

  robot.respond /lastfm (?:lp|last(?: played)?) (\S+)/i, (msg) ->
    alias = msg.match[1]
    last_fm.ifMember msg, alias, (nick) ->
      last_fm.getLatestTrack(nick).then (scrobble) ->
        artist = scrobble.last.artist
        track  = scrobble.last.track
        spotify.search(msg, artist, track).then (href) ->
          since  = moment.unix(scrobble.last.ts).fromNow()      
          msg.reply "#{alias} listened to #{artist} - #{track} (#{since})\n#{href}"

  robot.respond /lastfm np (\S+)/i, (msg) ->
    alias = msg.match[1]
    last_fm.ifMember msg, alias, (nick) ->
      last_fm.getLatestTrack(nick).then (scrobble) ->
        if scrobble.np
          artist = scrobble.np.artist
          track  = scrobble.np.track
          spotify.search(msg, artist, track).then (href) ->
            msg.reply "#{alias} listens to #{artist} - #{track}\n#{href}"
        else
          msg.reply "#{alias} enjoys the silence..."


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

  search: (msg, artist, track) ->
    def = deferred()
    url = "http://ws.spotify.com/search/1/track.json"
    options =
      q: "#{artist} - #{track}"
    msg.http(url).query(options).get() (err, resp, body) ->
      data = JSON.parse body
      if data.info.num_results > 0
        def.resolve data.tracks[0].href
      else
        def.resolve null
    def.promise


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

  getLatestTrack: (user) ->
    def = deferred()
    options =
      method: "user.getrecenttracks"
      user: user
      limit: 1
      nowplaying: '"true"'
    
    @client.scope().query(options).get() (err, resp, body) =>
      data = JSON.parse body
      track = data.recenttracks.track
      if _.isArray track
        [np, last] = track
        np =
          artist: np.artist["#text"]
          track: np.name
      else
        [np, last] = [null, track]

      def.resolve
        np: np
        last:
          artist: last.artist["#text"]
          track: last.name
          ts: last.date.uts

    def.promise

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

  ifMember: (msg, nick, cb) ->
    user = @lookupAlias nick
    if @isMember user
      cb(user)
    else
      msg.reply "not a valid last.fm user or alias"

  getAlias: (user) ->
    @robot.brain.data.lastfm[user] ? user

  lookupAlias: (lookupAlias) ->
    match = _.find _.pairs(@robot.brain.data.lastfm), (pair) ->
      [user, alias] = pair
      alias is lookupAlias
    if match then match[0] else lookupAlias

  isMember: (user) ->
    user in @users

  buildClient: ->
    options =
      api_key: @key
      format: "json"
    @client = @robot.http(LastFm.BASE_URL).query(options)
