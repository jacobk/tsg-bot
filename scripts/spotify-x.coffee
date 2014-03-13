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
querystring = require('querystring')


lastfm_key    = process.env.LAST_FM_KEY
lastfm_groups = process.env.LAST_FM_GROUPS || "tsg"
soundcloud_client_id = process.env.SOUNDCLOUD_CLIENT_ID

module.exports = (robot) ->

  last_fm = new LastFm lastfm_key, lastfm_groups, robot

  robot.hear spotify.link, (msg) ->
    msg.http(spotify.uri msg.match[0]).get() (err, res, body) ->
      if res.statusCode is 200
        data = JSON.parse(body)
        msg.send spotify[data.info.type](data)
        type = data.info.type
        if type in ["track", "album", "artist"]
          last_fm.getPlayCounts(type, data).then (listeners) ->
            if listeners.length > 0
              listeners = ("#{last_fm.getAlias user.user}(#{user.count})" for user in listeners)
              msg.send "Listeners: #{listeners.join(", ")}"

  # Totally hacked together support for SoundCloud URLs
  robot.hear soundcloud.link, (msg) ->
    options =
      url: msg.match[0]
      client_id: soundcloud_client_id
    msg.http(soundcloud.uri).query(options).get() (err, res, body) ->
      if res.statusCode is 302
        msg.http(JSON.parse(body).location).get() (err2, res2, body2) ->
          if res2.statusCode is 200
            data = JSON.parse(body2)
            if data.kind is "track"
              # Assume title includes title
              [artist, track] = data.title.split(/\s*-\s*/)

              # Nope, assume the username is the artist
              unless track
                track = artist
                artist = data.user.username

              # Fake spotify data format to make it work with lastfm-stuff
              spotifake =
                track:
                  name: track
                  artists: [name: artist]
              msg.send "Track: #{artist} - #{track}"
              last_fm.getPlayCounts("track", spotifake).then (listeners) ->
                if listeners.length > 0
                  listeners = ("#{last_fm.getAlias user.user}(#{user.count})" for user in listeners)
                  msg.send "Listeners: #{listeners.join(", ")}"

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
            msg.reply "#{alias} listens to #{artist} - #{track}\n#{href || '(not on spotify)'}"
            # Fake spotify data format to make it work with lastfm-stuff
            spotifake =
              track:
                name: track
                artists: [name: artist]
            last_fm.getPlayCounts("track", spotifake).then (listeners) ->
              if listeners.length > 0
                listeners = ("#{last_fm.getAlias user.user}(#{user.count})" for user in listeners)
                msg.send "Listeners: #{listeners.join(", ")}"
        else
          msg.reply "#{alias} enjoys the silence..."

  robot.respond /lastfm (\d+ )?trend(?:ing)? ?(?:this )?(week|month|year)?/i, (msg) ->
    nbrOfTracks = parseInt msg.match[1] ? 10, 10
    period = {week: "7day", month: "3month", year: "12month"}[msg.match[2]]
    period ?= "7day"
    last_fm.getTopTracks(nbrOfTracks, period).then (topTracks) ->
      msg.reply ("#{track[0]} (#{track[1]})" for track in topTracks).join(", ")

  robot.router.get '/hubot/spotify', (req, res) ->
    res.setHeader 'Content-Type', 'text/html'
    res.end listenersApp()

  robot.router.get '/hubot/spotify/listeners', (req, res) ->
    query = querystring.parse(req._parsedUrl.query)
    href = query.href
    robot.http(spotify.uri href).get() (err, resp, body) ->
      data = JSON.parse(body)
      track = spotify[data.info.type](data)
      type = data.info.type
      if type in ["track", "album", "artist"]
        last_fm.getPlayCounts(type, data).then (listeners) ->
          response =
            track: track,
            listeners: listeners
          res.setHeader 'Content-Type', 'application/json'
          res.end JSON.stringify(response)


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

soundcloud =
  link: /https?:\/\/soundcloud.com\S*/

  uri: "http://api.soundcloud.com/resolve.json"



class LastFm

  @BASE_URL = "http://ws.audioscrobbler.com/2.0/"

  constructor: (key, groups, robot) ->
    @key    = key
    @robot  = robot
    @buildClient()
    @getGroupMembers groups.split(/\s*,\s*/), (members) =>
      @users = members

  getPlayCounts: (type, data) ->
    def = deferred()
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
        def.resolve (user for user in result when user.count > 0)
      ),
      ((err) ->
        console.log "ERR", err
      )
    )
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

  getTopTracks: (nbrOfTracks, period) ->
    # TODO
    # * lookup on spotify
    # * show who listned to what (avaiable on groups page)
    def = deferred()
    options =
      method: "user.getTopTracks"
      period: period
      limit: 50

    userTopTracks = deferred.map @users, (user) =>
      @robot.logger.info "Getting to get top tracks for #{user}"
      options.user = user
      gettingTracks = deferred()
      @client.scope().query(options).get() (err, resp, body) =>
        data = JSON.parse(body)
        tracks = data.toptracks?.track ? []
        topTracks = {}
        for track in tracks
          fullTrack = "#{track.artist.name} - #{track.name}"
          topTracks[fullTrack] = parseInt(track.playcount, 10)
        @robot.logger.info "Got top tracks for #{user} (#{tracks.length} tracks)"
        gettingTracks.resolve topTracks
      gettingTracks.promise()

    userTopTracks.then (usersTracks) =>
      topTracks = {}
      for userTracks in usersTracks
        for track, count of userTracks
          topTracks[track] ?= 0
          topTracks[track] += count

      @robot.logger.debug JSON.stringify(topTracks)
      topTracks = _.sortBy _.pairs(topTracks), (pair) -> pair[1]
      def.resolve topTracks.reverse()[0...nbrOfTracks]

    def.promise()

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

listenersApp = () ->
  """
<!DOCTYPE html>
    <head>
        <meta charset="utf-8">
        <title>Links!</title>
        <link href="//netdna.bootstrapcdn.com/twitter-bootstrap/2.2.2/css/bootstrap-combined.min.css" rel="stylesheet">
        <style>
          body {
            margin-top: 70px;
          }
          form {
            margin-bottom: 30px;
          }
        </style>
    </head>
    <body>
        <div class="container">
        </div>
        <script src="//ajax.googleapis.com/ajax/libs/jquery/1.8.3/jquery.min.js"></script>
        <script src="//cdnjs.cloudflare.com/ajax/libs/underscore.js/1.4.3/underscore-min.js"></script>
        <script src="//cdnjs.cloudflare.com/ajax/libs/backbone.js/0.9.9/backbone-min.js"></script>
        <script src="//netdna.bootstrapcdn.com/twitter-bootstrap/2.2.2/js/bootstrap.min.js"></script>
        <script src="//cdnjs.cloudflare.com/ajax/libs/moment.js/1.7.2/moment.min.js"></script>


        <script type="text/template" id="search-query-tmpl">
          <div class="row">
            <div class="span8 offset2">
              <form class="form-search">
                <input type="text" class="input-xxlarge" placeholder="PUT SPOTIFY LINK HERE PLEASE">
                <button type="submit" class="btn">WHO WAS?</button>
              </form>
            </div>
          </div>
        </script>

        <script type="text/template" id="table-tmpl">
          <table class="table table-striped">
            <thead>
              <tr>
                <th>Listener</th>
                <th>Count</th>
              </tr>
            </thead>
            <tbody>
            </tbody>
          </table>
        </script>

        <script type="text/template" id="table-row-tmpl">
          <td><%= user %></td>
          <td><%= count %></td>
        </script>

        <script>
          var Query = Backbone.Model.extend({
            defaults: {
              href: ""
            }
          });

          var Listener = Backbone.Model.extend({});

          var Listeners = Backbone.Collection.extend({
            model: Listener,

            url: function() {
              return "/hubot/spotify/listeners?href=" + this.query.get("href");
            },

            initialize: function(models, query) {
              this.query = query;
              this.query.on("change:href", function() {
                this.fetch();
              }, this);
            },

            parse: function(response) {
              return response.listeners;
            }
          });

          var SearchView = Backbone.View.extend({
            template: _.template($("#search-query-tmpl").html()),

            events: {
              "click button": "onSearch"
            },

            initialize: function() {
              _.bindAll(this, "onSearch");
            },

            render: function() {
              this.$el.html(this.template(this.model.toJSON()));
              return this;
            },

            onSearch: function(e) {
              e.preventDefault();
              this.model.set("href", this.$("input").val());
            }
          });

          var ResultsView = Backbone.View.extend({
            template: _.template($("#table-tmpl").html()),

            initialize: function() {
              _.bindAll(this, "render");
              this.collection.on("change reset", this.render)
            },

            render: function() {
              this.$el.html(this.template());
              this.collection.each(function(listener) {
                var itemView = new ListenerView({
                  model: listener
                });
                this.$("tbody").append(itemView.render().el);
              }, this);
              return this;
            }
          });

          var ListenerView = Backbone.View.extend({
            template: _.template($("#table-row-tmpl").html()),

            tagName: "tr",

            render: function() {
              this.$el.html(this.template(this.model.toJSON()));
              return this;
            },
          });

          $(function() {
            var query = new Query(),
                listeners = new Listeners([], query),
                searchView = new SearchView({
                  model: query
                }),
                resultsView = new ResultsView({
                  collection: listeners
                });

            listeners.comparator = function(a) {
              return -a.get("count");
            };

            $(".container").append(searchView.render().el);
            $(".container").append(resultsView.render().el);
          });
        </script>
    </body>
</html>
"""