https = require('https');

parse_id    = process.env.PARSE_APP_ID
parse_key   = process.env.PARSE_API_KEY
parse_brain = process.env.PARSE_BRAIN

get_data = ->
  console.log "Retrieving old data"
  options =
    host: "api.parse.com"
    path: "/1/classes/brains/#{parse_brain}"
    headers:
      "Content-Type": "application/json"
      "X-Parse-Application-Id": parse_id
      "X-Parse-REST-API-Key": parse_key
    method: "get"

  req = https.request options, (res) ->
    res.setEncoding('utf8');
    body = ''
    res.on 'data', (chunk) ->
      body += chunk

    res.on 'end', ->
      handle_data JSON.parse(body)

  req.end()

handle_data = (data) ->
  old_version = data.links.version
  console.log "Found version #{old_version} data"
  if data.links.version isnt "1"
    throw "Cannot migrate from version #{data.links.version}"
  console.log "Migrating data to version 2"
  # Add id to all links
  # Convert poster array to object
  # Build the global index
  # Populate posters object
  # Change version number

  new_data = 
    version: "2"
    index: 0
    db: {}
    posters: {}

  links = for hash, link of data.links when hash isnt "version"
    link.posters = for poster in link.posters
      nick = poster[0]
      new_data.posters[nick] = (new_data.posters[nick] ? 0) + 1
      new_poster =
        nick: nick
        ts: parseInt(poster[1],10)
      new_poster
    [hash, link]

  links.sort (a, b) ->
    ats = a[1].posters[0].ts
    bts = b[1].posters[0].ts
    if ats is bts then 0 else (if ats < bts then -1 else 1)

  for pair in links
    [hash, link] = pair
    link.id = ++new_data.index
    new_data.db[hash] = link

  data.links = new_data
  save_data data

save_data = (data) ->
  console.log "Saving migrated data"
  json_data = JSON.stringify(data)

  options =
    host: "api.parse.com"
    path: "/1/classes/brains/#{parse_brain}"
    headers:
      "Content-Type": "application/json"
      "X-Parse-Application-Id": parse_id
      "X-Parse-REST-API-Key": parse_key
      "Content-Length": Buffer.byteLength(json_data)
    method: "put"

  req = https.request options, (res) ->
    res.setEncoding('utf8');
    body = ''
    res.on 'data', (chunk) ->
      body += chunk

    res.on 'end', ->
      console.log "Status", res.statusCode
      console.log "Response", body
      console.log "Done!"

  req.end(json_data)


get_data()