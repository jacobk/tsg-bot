// Usage:
// node gen_spotify_grant.js --ngrok <url> --id <client id> --secret <client secret> --code <grant code>

var argv = require('minimist')(process.argv.slice(2));

var SpotifyWebApi = require('spotify-web-api-node'),
    redirectUri = argv.ngrok,
    clientId = argv.id,
    clientSecret = argv.secret,
    code = argv.code,
    spotifyApi = new SpotifyWebApi({
      redirectUri : redirectUri,
      clientId : clientId,
      clientSecret : clientSecret
    });


spotifyApi.authorizationCodeGrant(code)
  .then(function(data) {
    console.log('The token expires in ' + data['expires_in']);
    console.log('The access token is ' + data['access_token']);
    console.log('The refresh token is ' + data['refresh_token']);
  }, function(err) {
    console.log('Something went wrong!', err);
  });
