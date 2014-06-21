var util = require('util'),
    SpotifyWebApi = require('spotify-web-api-node');
    _ = require('lodash');

function Spotify(clientId, clientSecret) {
  this.client = new SpotifyWebApi();
  // @client = new SpotifyWebApi
  //   clientId: clientId
  //   clientSecret: clientSecret

  // @client.clientCredentialsGrant().then(
  //   ((data) =>
  //     console.log('The access token expires in ' + data['expires_in'])
  //     console.log('The access token is ' + data['access_token'])
  //     @client.setAccessToken(data['access_token']))
  // )
}

module.exports = Spotify;

Spotify.prototype.link = /(?:http:\/\/open.spotify.com\/|spotify:)(track|album|artist)(?:\/|:)(\S+)/;

Spotify.prototype.lookup = function(type, id, format) {
  var self = this,
      methods = {
        track: 'getTrack',
        artist: 'getArtist',
        album: 'getAlbum'
      },
      method = methods[type],
      res = {};

  function handleResponse(data) {
    var formatted = self.formats[format][type](data);
    res.data = data;
    res.formatted = formatted;
    return res;
  }

  function handleError(err) {
    console.error('Spotify error', err);
  }

  return this.client[method](id).then(handleResponse, handleError);
};

Spotify.prototype.search = function(artist, track, format) {
  var self = this,
      query = util.format('artist:%s track:%s', artist, track),
      res = {};

  function handleResponse(data) {
    var hit = data.tracks.items[0];
    if (hit) {
      res.formatted = self.formats[format].trackLink(hit);
      res.data = hit;
    }
    return res;
  }

  function handleError(err) {
    console.error('Spotify error', err);
  }

  return this.client.searchTracks(query).then(handleResponse, handleError);
};

var formatArtists = function(artists) {
  return _.map(artists, function(artist) {
    return artist.name;
  }).join(',');
};

Spotify.prototype.formats = {
  html: {
    track: function(data) {
      var artists = formatArtists(data.artists);
      var track = util.format('<b>%s - %s</b>', artists, data.name);
      var album = util.format('<i>(%s)</i>', data.album.name);
      return util.format("Track: %s %s", track, album);
    },
    album: function(data) {
      var artists = formatArtists(data.artists);
      var format = 'Album: <b>%s</b> - <i>%s</i> (%s)';
      return util.format(format, artists, data.name, data.release_date);
    },
    artist: function(data) {
      return util.format('Arist: <b>%s</b>', data.name);
    },
    trackLink: function(data) {
      var web = util.format('<a href="%s">web</a>', data.external_urls.spotify);
      var preview = util.format('<a href="%s">preview</a>', data.preview_url);
      var popularity = util.format('popularity: <b>%s%</b>', data.popularity);
      return util.format('Links: %s %s %s %s', data.uri, web, preview, popularity);
    }
  }
};
