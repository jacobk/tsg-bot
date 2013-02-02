# Description:
#   None
#
# Dependencies:
#   None
#
# Configuration:
#   PARSE_APP_ID
#   PARSE_API_KEY
#   PARSE_BRAIN - Parse brains class objectId to use
#
# Commands:
#   None
#
# Author:
#   jacobk


parse_id    = process.env.PARSE_APP_ID
parse_key   = process.env.PARSE_API_KEY
parse_brain = process.env.PARSE_BRAIN


module.exports = (robot) ->
  client = new Parse(parse_id, parse_key, parse_brain, robot)
  client.sync()
  
  robot.brain.on "save", client.save


class Parse

  @BASE_URL = "https://api.parse.com/1/classes/brains/"

  constructor: (id, key, brain_id, robot) ->
    @id       = id
    @key      = key
    @brain_id = brain_id
    @robot    = robot
    @buildClient()
    @robot.brain.resetSaveInterval 10 # Don't flood parse (1M limit/month)

  sync: ->
    @client.get() (err, resp, body) =>
      console.error "Failed to sync with Parse.com" unless resp.statusCode is 200
      @robot.brain.mergeData JSON.parse(body)

  save: (data) =>
    json_data = JSON.stringify(data)
    @client.scope()
      # Manually set content length and using streaming body handler
      # to deal with scoped-client's inability to send multi byte unicode
      .header("Content-Length", Buffer.byteLength(json_data))
      .put((err, req) -> req.end json_data) (err, resp, body) =>
          console.error "Failed to save to Parse.com" unless resp.statusCode is 200    

  buildClient: ->
    @client = @robot.http(@brainUrl())
      .header("X-Parse-Application-Id", @id)
      .header("X-Parse-REST-API-Key", @key)
      .header("Content-Type", "application/json")

  brainUrl: ->
    "#{Parse.BASE_URL}#{@brain_id}"
