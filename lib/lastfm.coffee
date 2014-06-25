deferred = require "deferred"
moment = require "moment"

class LastFm

  @BASE_URL = "http://ws.audioscrobbler.com/2.0/"

  constructor: (key, groups, robot) ->
    @key    = key
    @robot  = robot
    @buildClient()
    @getGroupMembers groups.split(/\s*,\s*/), (members) =>
      @users = members
    @formats.html.listeners.bind(@)

  getPlayCounts: (type, data, format) ->
    def = deferred()
    res = {}
    options = method: "#{type}.getInfo"
    @assignSpotifyData options, type, data

    @robot.logger.debug 'Getting lastfm play counts', type, format, JSON.stringify(options)

    counts = deferred.map @users, (user) =>
      @getPlayCount(type, options, user)

    counts.then(
      ((result) =>
        @robot.logger.debug 'Got playcounts', result
        listeners = (user for user in result when user.count > 0)
        if listeners.length > 0
          res.listeners = listeners
          res.formatted = @formats[format].listeners(listeners)
        def.resolve res
      ),
      ((err) ->
        console.log "ERR", err
      )
    )
    def.promise

  getTopTags: (type, data, format) ->
    def = deferred()
    res = {}
    options = method: "#{type}.getTopTags"
    @assignSpotifyData options, type, data

    @robot.logger.debug 'Getting lastfm top tags', type, JSON.stringify(options)

    @client.scope().query(options).get() (err, resp, body) =>
      data = JSON.parse body
      unless data.error
        def.resolve (tag.name for tag in data.toptags.tag)
      else
        console.log "Last.fm failure", body
        def.resolve new Error("Failed to get playcount")

    def.promise

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
    @robot.logger.debug 'Getting playcount', JSON.stringify(options)
    @client.scope().query(options).get() (err, resp, body) =>
      data = JSON.parse body
      unless data.error
        if type == "artist"
          def.resolve
            user: user
            count: data[type].stats.userplaycount
        else
          def.resolve
            user: user
            count: data[type].userplaycount
      else
        console.log "Last.fm failure", body
        def.resolve new Error("Failed to get playcount")

    def.promise

  getGroupMembers: (groups, callback) ->
    @robot.logger.info "Last.fm getting members for groups #{groups}"
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

  getGroupRecentTracks: (nbrOfTracks, groupByArtist=false) ->
    def = deferred()
    from = if moment().hours() < 4 then (moment().hours(4).minutes(0).subtract('days', 1)) else (moment().hours(4).minutes(0).unix())
    options =
      method: "user.getRecentTracks"
      from: from
      limit: 50

    trackKey =
      if groupByArtist
        (track) -> track.artist['#text']
      else
        (track) -> "#{track.artist['#text']} - #{track.name}"

    membersRecentTracksP = deferred.map @users, (user) =>
      @robot.logger.info "Getting to get recent tracks for #{user}"
      options.user = user
      recentTracksP = deferred()
      @client.scope().query(options).get() (err, resp, body) =>
        data = JSON.parse(body)
        tracks = data.recenttracks?.track ? []
        recentTracks = {}
        for track in tracks
          tk = trackKey track
          recentTracks[tk] ?= []
          recentTracks[tk].push user
        @robot.logger.info "Got recent tracks for #{user} (#{tracks.length} tracks)"
        recentTracksP.resolve recentTracks
      recentTracksP.promise()

    membersRecentTracksP.then (usersTracks) =>
      def.resolve @compileTopTrackStats usersTracks, nbrOfTracks

    def.promise()

  getTopTracks: (nbrOfTracks, period, groupByArtist=false) ->
    # TODO
    # * lookup on spotify
    # * show who listned to what (avaiable on groups page)
    def = deferred()
    options =
      method: "user.getTopTracks"
      period: period
      limit: 200

    trackKey =
      if groupByArtist
        (track) -> track.artist.name
      else
        (track) -> "#{track.artist.name} - #{track.name}"

    userTopTracks = deferred.map @users, (user) =>
      @robot.logger.info "Getting to get top tracks for #{user}"
      options.user = user
      gettingTracks = deferred()
      @client.scope().query(options).get() (err, resp, body) =>
        data = JSON.parse(body)
        tracks = data.toptracks?.track ? []
        topTracks = {}
        for track in tracks
          tk = trackKey track
          count = parseInt(track.playcount, 10)
          topTracks[tk] ?= []
          Array.prototype.push.apply topTracks[tk], (user for x in [1..count])
        @robot.logger.info "Got top tracks for #{user} (#{tracks.length} tracks)"
        gettingTracks.resolve topTracks
      gettingTracks.promise()

    userTopTracks.then (usersTracks) =>
      def.resolve @compileTopTrackStats usersTracks, nbrOfTracks

    def.promise()

  compileTopTrackStats: (usersTracks, nbrOfTracks) ->
    topTracks = {}
    for userTracks in usersTracks
      for track, listeners of userTracks
        topTracks[track] ?= []
        Array.prototype.push.apply topTracks[track], listeners
    topTracks = _.sortBy _.pairs(topTracks), (pair) -> pair[1].length
    topTracks.reverse()[0...nbrOfTracks]


  ifMember: (msg, nick, cb) ->
    user = @lookupAlias nick
    if @isMember user
      cb(user)
    else
      msg.reply "not a valid last.fm user or alias"

  getAlias: (user) ->
    user
    # @robot.brain.data.lastfm[user] ? user

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

  assignSpotifyData: (options, type, data) ->
    if type is "track"
      options.artist = data.artists[0].name
      options.track  = data.name
    else if type is "album"
      options.artist = data.artists[0].name
      options.album  = data.name
    else if type is "artist"
      options.artist = data.name

  formats:
    html:
      listeners: (data) ->
        pieces = ("#{user.user}<i>(#{user.count})</i>" for user in data)
        "Listeners: #{pieces.join(", ")}"

module.exports = LastFm