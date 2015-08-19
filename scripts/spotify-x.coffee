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

moment = require "moment"
querystring = require('querystring')
deferred = require "deferred"
_ = require "lodash"

LastFm = require('../lib/lastfm')
Spotify = require('../lib/spotify')
Hipchat = require('../lib/hipchat')

lastfm_key    = process.env.LAST_FM_KEY
lastfm_groups = process.env.LAST_FM_GROUPS || "tsg"
hipchat_key = process.env.HIPCHAT_API_KEY
soundcloud_client_id = process.env.SOUNDCLOUD_CLIENT_ID
spotify_playlist_user = process.env.SPOTIFY_PLAYLIST_USER
spotify_playlist_id = process.env.SPOTIFY_PLAYLIST_ID
spotify_client_id = process.env.SPOTIFY_CLIENT_ID
spotify_client_secret = process.env.SPOTIFY_CLIENT_SECRET
spotify_refresh_token = process.env.SPOTIFY_REFRESH_TOKEN

format = 'html'

module.exports = (robot) ->

  robot.brain.on "loaded", ->
    last_fm = new LastFm(lastfm_key, lastfm_groups, robot)
    spotify = new Spotify(spotify_client_id, spotify_client_secret, spotify_refresh_token);
    hipchat = new Hipchat(robot, hipchat_key)

  # last_fm = new LastFm(lastfm_key, lastfm_groups, robot)
  # spotify = new Spotify(spotify_client_id, spotify_client_secret, spotify_refresh_token);
  # hipchat = new Hipchat(robot, hipchat_key)

  hc_params = (from, message) ->
    from: from
    message: message
    format: format
    color: "gray"

  show_listeners = (msg, type, data) ->
    def = deferred()
    last_fm.getPlayCounts(type, data, format).then (listeners) ->
      if listeners.listeners
        hipchat.postMessage hc_params('last.fm', listeners.formatted), msg
      def.resolve listeners
    def.promise

  show_spotify_info = (msg, data) ->
    robot.logger.debug "Showing spotify info"
    def = deferred()
    spotify.search(data, format).then (res) ->
      message = "<i>No spotify info</i>"
      if res.data
        message = res.formatted
        # spotify.addToPlaylist(spotify_playlist_user, spotify_playlist_id,
        #   res.data.uri);
      hipchat.postMessage hc_params('Spotify', message), msg
      def.resolve listeners
    def.promise

  show_lastfm_info = (msg, type, data) ->
    def = deferred()
    last_fm.getTopTags(type, data, format).then (res) ->
      message = "Tags: <i>#{res[0..5].join(", ")}</i>"
      hipchat.postMessage hc_params('last.fm', message), msg
      def.resolve true
    def.promise

  spotifake = (artist, track) ->
    name: track
    artists: [name: artist]

  aggregateTopTracks = (topTrack) ->
    histogram = {}
    for listener in topTrack[1]
      histogram[listener] ?= 0
      histogram[listener] += 1
    histogram

  robot.hear spotify.link, (msg) ->
    type = msg.match[1]
    id = msg.match[2]
    if /^links:/i.test msg.message.text
      return
    spotify.lookup(type, id, format).then (res) ->
      hipchat.postMessage hc_params('Spotify', res.formatted), msg
      if type is "track"
        show_spotify_info msg, res.data
      show_listeners msg, type, res.data
      # show_lastfm_info msg, type, res.data

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

              message = "Track: <b>#{artist} - #{track}</b>"
              hipchat.postMessage hc_params('Soundcloud', message), msg
              show_listeners msg, "track", spotifake(artist, track), format

  robot.respond /(spotify )?playlist/i, (msg) ->
    msg.reply "spotify:user:#{spotify_playlist_user}:playlist:#{spotify_playlist_id}"

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
    alias = msg.match[1] or msg.message.mention_name
    last_fm.ifMember msg, alias, (nick) ->
      last_fm.getLatestTrack(nick).then (scrobble) ->
        artist = scrobble.last.artist
        track  = scrobble.last.track
        since  = moment.unix(scrobble.last.ts).fromNow()
        message = "#{alias} listened to <b>#{artist} - #{track}</b> <i>(#{since})</i>"
        hipchat.postMessage hc_params('last.fm', message), msg
        show_spotify_info msg, spotifake(artist, track)
        # show_lastfm_info msg, "track", spotifake(artist, track), format
        show_listeners msg, "track", spotifake(artist, track), format

  show_np = (msg) ->
    alias = msg.match[1] or msg.message.user.mention_name
    last_fm.ifMember msg, alias, (nick) ->
      last_fm.getLatestTrack(nick).then (scrobble) ->
        if scrobble.np
          artist = scrobble.np.artist
          track  = scrobble.np.track
          message = "Track: <b>#{artist} - #{track}</b>"
          hipchat.postMessage hc_params('last.fm', message), msg
          show_spotify_info msg, spotifake(artist, track)
          # show_lastfm_info msg, "track", spotifake(artist, track), format
          show_listeners msg, "track", spotifake(artist, track), format
        else
          message = "<i>#{alias} enjoys the silence...</i>"
          hipchat.postMessage hc_params("last.fm", message), msg

  robot.respond /lastfm np (\S+)/i, (msg) ->
    show_np msg

  robot.hear /^np/i, (msg) ->
    show_np msg

  robot.respond /lastfm (\d+ )?trending ?(artists?|tracks?)? ?(?:this )?(now|week|month|year)?/i, (msg) ->
    nbrOfTracks = parseInt msg.match[1] ? 10, 10
    groupByArtist = true if /^artist/.test msg.match[2]
    period = {week: "7day", month: "3month", year: "12month"}[msg.match[3]]
    period ?= "now"

    formatter = (topTracks) ->
      lines = for track,idx in topTracks
        listeners = aggregateTopTracks track
        pieces = ("#{user}<i>(#{count})</i>" for user, count of listeners)
        "<li><b>#{track[0]}</b> [#{track[1].length}] #{pieces.join(", ")}</li>"

      "<ol>#{lines.join("")}</ol>"
      # ("##{idx+1}(#{track[1].length})> #{track[0]}" for track,idx in topTracks).join(" -- ")

    saveTopTracks = (topTracks) ->
      robot.brain.data.lastTopTracks = topTracks

    if period is "now"
      last_fm.getGroupRecentTracks(nbrOfTracks, groupByArtist).then (topTracks) ->
        saveTopTracks(topTracks)
        hipchat.postMessage hc_params('last.fm', formatter(topTracks)), msg
    else
      last_fm.getTopTracks(nbrOfTracks, period, groupByArtist).then (topTracks) ->
        saveTopTracks(topTracks)
        hipchat.postMessage hc_params('last.fm', formatter(topTracks)), msg

  robot.respond /lastfm who\s?(?:is)? #?(\d+)/i, (msg) ->
    tracks = robot.brain.data.lastTopTracks
    if tracks?
      idx = parseInt msg.match[1], 10
      track = tracks[idx-1]
      if track?
        histogram = {}
        for listener in track[1]
          histogram[listener] ?= 0
          histogram[listener] += 1
        listeners = ("#{last_fm.getAlias user}(#{count})" for user, count of histogram)
        msg.send "Listeners: #{listeners.join(", ")}"
      else
        msg.reply "IndexOutOfFuckingBoundsExFuckingCeption"
    else
      msg.reply "Sorry, don't know what's trending"

  robot.respond /lastfm[?]/i, (msg) ->
    usage = """Last played track for nick -> /lastfm (?:lp|last(?: played)?) (\S+)/
    Currently playing track for nick -> /lastfm np (\S+)/
    Show aggregated top tracks for lastfm group -> /lastfm (\d+ )?trend(?:ing)? ?(?:this )?(week|month|year)?/"""
    msg.send usage

  robot.router.get '/hubot/spotify', (req, res) ->
    res.setHeader 'Content-Type', 'text/html'
    res.end listenersApp()

  robot.router.get '/hubot/spotify/play', (req, res) ->
    urlencode = require 'urlencode';
    query = querystring.parse(req._parsedUrl.query)
    uri = urlencode(query.uri)
    body = "<iframe src='https://embed.spotify.com/?uri=#{uri}' width='300' height='380' frameborder='0' allowtransparency='true'></iframe>"
    res.setHeader 'Content-Type', 'text/html'
    res.end body

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


soundcloud =
  link: /https?:\/\/soundcloud.com\S*/

  uri: "http://api.soundcloud.com/resolve.json"


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
