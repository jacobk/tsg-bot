// Usage:
// node gen_spotify_grant.js --ngrok <url> --id <client id> --secret <client secret>

var argv = require('minimist')(process.argv.slice(2));

var SpotifyWebApi = require('spotify-web-api-node'),
    scopes = ['playlist-modify-public', 'playlist-modify-private'],
    redirectUri = argv.ngrok,
    state = 'yolo',
    clientId = argv.id,
    clientSecret = argv.secret,
    spotifyApi = new SpotifyWebApi({
      redirectUri : redirectUri,
      clientId : clientId
    });


console.log('Run "ngrok 12345"');
console.log('Run "nc -l 12345"');
console.log('Browse to', spotifyApi.createAuthorizeURL(scopes, state));
console.log('Save the "code" query param');
