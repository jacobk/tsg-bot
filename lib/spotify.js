var util = require('util'),
    SpotifyWebApi = require('spotify-web-api-node');
    _ = require('lodash');

function Spotify(clientId, clientSecret) {
  this.client = new SpotifyWebApi();
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
      var web = util.format('<a href="%s">web</a>', data.external_urls.spotify);
      var preview = util.format('<a href="%s">preview</a>', data.preview_url);
      var popularity = util.format('popularity: <b>%s%</b>', data.popularity);
      return util.format('Links: %s %s %s %s', data.uri, web, preview, popularity);
    }
  }
};
