var util = require('util'),
    SpotifyWebApi = require('spotify-web-api-node'),
    _ = require('lodash'),
    heroku_url = (process.env.HEROKU_URL || 'http://localhost:8080');

function Spotify(clientId, clientSecret, refreshToken) {
  console.log('Init spotify', clientId, clientSecret, refreshToken);
  this.client = new SpotifyWebApi({
    refreshToken: refreshToken,
    clientId: clientId,
    clientSecret: clientSecret
  });
}

module.exports = Spotify;

Spotify.prototype.link = /(?:https?:\/\/open.spotify.com\/|spotify:)(track|album|artist)(?:\/|:)(\S+)/;

Spotify.prototype.lookup = function(type, id, format) {
  var self = this,
      methods = {
        track: 'getTrack',
        artist: 'getArtist',
        album: 'getAlbum'
      },
      method = methods[type];

  function handleError(err) {
    console.error('Spotify error', err);
  }

  function getFullAlbumIfTrack(data) {
    console.log('getFullAlbumIfTrack', data);
    if (type === 'track') {
      console.log('getting full album with id', data.id);
      return self.client.getAlbum(data.album.id).then(function(albumData) {
        data.album = albumData;
        return data;
      });
    } else {
      return data;
    }
  }

  function processResults(data) {
    var formatted = self.formats[format][type](data);
    var res = {};
    res.data = data;
    res.formatted = formatted;
    return res;
  }

  return this.client[method](id)
    .then(getFullAlbumIfTrack, handleError)
    .then(processResults, handleError);
};

Spotify.prototype.search = function(data, format) {
  var self = this,
      artist = data.artists[0].name,
      track = data.name,
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

var formatAlbumHTML = function(album) {
  var genres = _.isEmpty(album.genres) ? 'No genre' : album.genres.join(', ');
  return util.format('<i>(%s)</i> (%s / %s)', album.name,
        album.release_date, genres);
};

Spotify.prototype.formats = {
  html: {
    track: function(data) {
      var artists = formatArtists(data.artists);
      var track = util.format('<b>%s - %s</b>', artists, data.name);
      var album = formatAlbumHTML(data.album);
      return util.format("Track: %s %s", track, album);
    },
    album: function(data) {
      var artists = formatArtists(data.artists);
      var format = 'Album: <b>%s</b> - %s';
      return util.format(format, artists, formatAlbumHTML(data));
    },
    artist: function(data) {
      return util.format('Arist: <b>%s</b>', data.name);
    },
    trackLink: function(data) {
      var play = util.format('<a href="%shubot/spotify/play?uri=%s">play</a>', heroku_url, data.uri);
      var web = util.format('<a href="%s">web</a>', data.external_urls.spotify);
      var preview = util.format('<a href="%s">preview</a>', data.preview_url);
      var popularity = util.format('popularity: <b>%s%</b>', data.popularity);
      return util.format('Links: %s %s %s %s %s', data.uri, play, web, preview, popularity);
    }
  }
};

Spotify.prototype.addToPlaylist = function(user, playlist, trackUri) {
  console.log('Adding to playlist', user, playlist, trackUri);
  var authorizedClient = new SpotifyWebApi({
    refreshToken: this.getRefreshRoken(),
    clientId: this.getClientId(),
    clientSecret: this.getClientSecret()
  });
  this.client.refreshAccessToken()
    .then(function(data) {
      console.log('Token refreshed', data);
      authorizedClient.setAccessToken(data.access_token);
      authorizedClient.addTracksToPlaylist(user, playlist, [trackUri])
        .then(function(data) {
          console.log('Added tracks to playlist!');
        }, function(err) {
          console.log('Something went wrong!', err);
        });
    }, function(err) {
      console.log('Could not refresh access token', err);
    });
};